# frozen_string_literal: true

require "prism"
require "set"
require "open3"
require "strscan"
require_relative "ast_fixer/syntax_transforms"
require_relative "ast_fixer/web_transforms"
require_relative "ast_fixer/dead_code_and_commas"

module Master
  module Review
    module Scan
      # Architecture #4: deterministic AST-level autofixes for mechanical rules.
      # No LLM call, no token cost. Applied before LLM sweep on every scan cycle.
      # Each transform is idempotent — safe to apply repeatedly.
      #
      # This class is dispatch plus the four whitespace transforms that need no
      # knowledge of the source at all: pick the strategies whose predicate
      # matches the path, run their transforms in order, refuse any transform
      # that turns parseable Ruby into unparseable Ruby, write back. Everything
      # that has to know something — the language's syntax, HTML/JS/CSS, or
      # which lines sit inside multi-line literals — lives in a mixin.
      class AstFixer
        JS_EXTS = %w[.js .ts .jsx .tsx].freeze
        STYLE_EXTS = %w[.css .scss].freeze

        Result = Struct.new(:path, :changed, :transforms, keyword_init: true)
        Strategy = Struct.new(:predicate, :transforms, keyword_init: true)
        STRATEGIES = [
          Strategy.new(predicate: :ruby?, transforms: %i[add_frozen_header fix_bare_rescue freeze_mutable_constants remove_immediate_dead_code add_trailing_commas]),
          Strategy.new(predicate: :sql_context?, transforms: %i[normalise_null_comparison]),
          Strategy.new(predicate: :shell?, transforms: %i[add_strict_mode]),
          Strategy.new(predicate: :html?, transforms: %i[add_html_lang add_meta_charset add_viewport_fit add_skip_to_main add_lazy_loading]),
          Strategy.new(predicate: :javascript?, transforms: %i[replace_unreassigned_var convert_for_in_arrays convert_string_concat convert_optional_chaining]),
          Strategy.new(predicate: :style?, transforms: %i[logical_properties]),
        ].freeze
        # remove_immediate_dead_code/add_trailing_commas are Ruby-AST heuristics
        # (Prism-based literal-line protection, Ruby hash/array trailing-comma
        # convention) -- they used to sit here and run against every file type.
        # On non-Ruby source, Prism.parse fails, literal_lines comes back empty,
        # the heuristics run fully unguarded, AND apply_transforms's own
        # parses?-before/after safety net only fires `if ruby?` -- so a broken
        # transform on a .js/.css file had zero backstop. Confirmed in production:
        # add_trailing_commas turned every CSS rule's closing `}` into a trailing
        # `,` (e.g. `--z-skip: 2000;` + `}` -> `--z-skip: 2000;,`), and
        # remove_immediate_dead_code deleted live sibling if-branches in chat.js
        # that only *looked* unreachable without real block-scope analysis.
        # Now Ruby-only, via the ruby? strategy above.
        UNIVERSAL_TRANSFORMS = %i[expand_tabs collapse_blank_lines strip_trailing_whitespace ensure_final_newline].freeze

        include SyntaxTransforms
        include WebTransforms
        include DeadCodeAndCommas

        def self.fix(path, source, event_bus: nil)
          new(path, source, event_bus:).apply
        end

        def initialize(path, source, event_bus: nil)
          @path = path
          @source = source
          @bus = event_bus
          @transforms = []
        end

        # OPENBSD/etc, /usr and /var mirror files installed verbatim on the VPS
        # — newsyslog.conf's own header says taken verbatim from etc.tgz and
        # validated before installing, and tabs are load-bearing in
        # termcap-style files like login.conf. A rewrite here breaks
        # diffability against upstream at best and a daemon at worst; on
        # 2026-08-18 one pass re-indented login.conf, newsyslog.conf and an
        # rc.d script and injected strict mode into cron scripts written to
        # tolerate failure.
        VERBATIM_MIRROR_RE = %r{/OPENBSD/(?:etc|usr|var)/}

        def apply
          return Result.new(path: @path, changed: false, transforms: []) if verbatim_mirror?

          out = @source
          out = apply_strategies(out)
          changed = out != @source
          Result.new(path: @path, changed:, transforms: @transforms)
            .tap { publish_and_write(out) if changed }
        end

        private

        def apply_strategies(src)
          out = apply_transforms(src, UNIVERSAL_TRANSFORMS.first(2))
          applicable_strategies.each do |strategy|
            out = apply_transforms(out, strategy.transforms)
          end
          apply_transforms(out, UNIVERSAL_TRANSFORMS.drop(2))
        end

        def applicable_strategies
          STRATEGIES.select { |strategy| send(strategy.predicate) }
        end

        # An explicit accumulator loop, deliberately — not reduce, not
        # each_with_object.
        #
        # The accumulator is the rewritten source, so each step must produce the
        # next value. each_with_object returns the object and throws the block
        # result away, which turns every transform into a no-op; all thirteen
        # transform tests fail at once and nothing else does.
        #
        # It has been written as `reduce(src)` and rewritten to
        # `each_with_object(src)` twice, by the LLM fix sweep applying rule
        # EACH_WITH_OBJECT (data/rules.yml line). That rule's lexical detector
        # requires `reduce({})` — a fresh empty hash — and never matched this
        # line; the sweep applied it from the rule's *name* instead. Fixed once
        # in 5d8d49401, reintroduced by 8962ce5f7, and again after 4e964ce12.
        #
        # So this is written as a plain loop with a named accumulator: there is
        # no `reduce` for that rule to recognise, and the data-flow is on the
        # page rather than in a method's return-value contract. The rule has
        # also been narrowed, but the code should not depend on that.
        def apply_transforms(src, transforms)
          current = src
          transforms.each do |transform|
            transform_labels = @transforms.dup
            candidate = send(transform, current)

            if candidate != current && broke_syntax?(current, candidate)
              # Transform turned valid source into unparseable source — a
              # line-heuristic misfire on a multi-line construct. Discard it
              # (and any label it recorded); keep the prior source.
              @transforms.replace(transform_labels)
              next
            end

            current = candidate
          end
          current
        end

        # The net used to cover Ruby only, so a JS or CSS transform that mangled
        # a multi-line construct had no backstop at all — the exact asymmetry
        # that let add_trailing_commas rewrite every CSS `}` as `;,` in
        # production. Same shape as the Ruby check in all three languages: a
        # transform is discarded only when the source parsed BEFORE it and stops
        # parsing after. When no validator is available for a language (no node
        # on PATH for JS), nothing is measured and nothing is judged.
        def broke_syntax?(before, after)
          validator = syntax_validator
          return false unless validator
          return false unless send(validator, before)

          !send(validator, after)
        end

        def syntax_validator
          return :parses? if ruby?
          return :javascript_parses? if javascript? && self.class.node_available?
          return :style_balanced? if style?

          nil
        end

        def parses?(src) = !Prism.parse(src).failure?

        # Both module and script parses are tried because a bundle using
        # `import` is invalid as a script and a file using `with` is invalid as
        # a module; accepting either keeps the check a syntax test rather than a
        # module-system opinion.
        def javascript_parses?(src)
          %w[module commonjs].any? { |mode| node_accepts?(src, mode) }
        end

        def node_accepts?(src, mode)
          _out, status = Open3.capture2e("node", "--input-type=#{mode}", "--check", stdin_data: src)
          status.success?
        rescue StandardError
          false
        end

        def self.node_available?
          return @node_available unless @node_available.nil?

          @node_available = ENV["PATH"].to_s.split(File::PATH_SEPARATOR).any? do |dir|
            File.executable?(File.join(dir, "node"))
          end
        end

        # CSS has no cheap parser to hand, but every failure this net exists to
        # catch shows up as an unbalanced block. Quotes and comments are skipped
        # so a brace inside `content: "}"` does not read as structure.
        def style_balanced?(src)
          depth = 0
          scanner = StringScanner.new(src)
          until scanner.eos?
            case
            when scanner.scan(%r{/\*.*?\*/}m) then next
            when scanner.scan(/"(?:[^"\\]|\\.)*"/) then next
            when scanner.scan(/'(?:[^'\\]|\\.)*'/) then next
            when scanner.scan(/\{/) then depth += 1
            when scanner.scan(/\}/) then depth -= 1
            else scanner.pos += 1
            end
            return false if depth.negative?
          end
          depth.zero?
        end

        # Tabs are syntax in make recipes, the delimiter in TSV, gofmt's
        # output in Go, and convention in .conf mirrors — expanding them is a
        # break, not a cleanup. dilla's demo_manifest.tsv lost its columns to
        # this on 2026-08-18.
        TAB_SIGNIFICANT_RE = /\A(?:makefile.*|.*\.(?:mk|conf|tsv|go))\z/i

        def expand_tabs(src)
          return src unless src.include?("\t")
          return src if TAB_SIGNIFICANT_RE.match?(File.basename(@path.to_s))

          out = src.gsub("\t", "  ")
          @transforms << :expand_tabs if out != src
          out
        end

        def collapse_blank_lines(src)
          out = src.gsub(/(\n\n)\n+/, "\\1")
          @transforms << :collapse_blank_lines if out != src
          out
        end

        def strip_trailing_whitespace(src)
          out = if markdown?
                  # Two or more trailing spaces are a Markdown hard line
                  # break. Strip whitespace-only lines and single stray
                  # blanks; leave the breaks standing.
                  src.gsub(/^[ \t]+$/, "").gsub(/(?<=[^ \t\n])[ \t](?=\n|\z)/, "")
                else
                  src.gsub(/[ \t]+(?=\n|\z)/, "")
                end
          @transforms << :trailing_whitespace if out != src
          out
        end

        def ensure_final_newline(src)
          return src if src.empty? || src.end_with?("\n")

          @transforms << :final_newline
          src + "\n"
        end

        def publish_and_write(out)
          write_back(out)
          @bus&.publish("ast_fixer:transform", path: @path, transforms: @transforms)
        end

        def ruby? = File.extname(@path).downcase == ".rb"

        def markdown? = File.extname(@path).downcase == ".md"

        def verbatim_mirror? = @path.to_s.match?(VERBATIM_MIRROR_RE)

        def shell? = %w[.zsh .sh .bash].include?(File.extname(@path).downcase)

        def html? = %w[.html .erb .html.erb].any? { |ext| @path.to_s.downcase.end_with?(ext) }

        def javascript? = JS_EXTS.include?(File.extname(@path).downcase)

        def style? = STYLE_EXTS.include?(File.extname(@path).downcase)

        def sql_context?
          ruby? || %w[.sql .erb].include?(File.extname(@path).downcase)
        end

        def write_back(content)
          temporary_path = "#{@path}.ast_fix.#{Process.pid}.tmp"
          File.write(temporary_path, content, encoding: "UTF-8")
          # rename replaces the inode, so the original's mode must travel with
          # the content — three executable cron scripts came back 0644 from
          # one pass before this line existed.
          File.chmod(File.stat(@path).mode, temporary_path) if File.exist?(@path)
          File.rename(temporary_path, @path)
        rescue StandardError => e
          delete_temporary_path(temporary_path) if defined?(temporary_path)
          raise e
        end

        def delete_temporary_path(path)
          File.delete(path) if path && File.exist?(path)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "AstFixer.delete_temporary_path")
          nil
        end
      end
    end
  end
end
