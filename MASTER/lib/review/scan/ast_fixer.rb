# frozen_string_literal: true

require "prism"
require "set"
require_relative "ast_fixer/web_transforms"
require_relative "ast_fixer/dead_code_and_commas"

module Master
  module Review
    module Scan
      # Architecture #4: deterministic AST-level autofixes for mechanical rules.
      # No LLM call, no token cost. Applied before LLM sweep on every scan cycle.
      # Each transform is idempotent — safe to apply repeatedly.
      class AstFixer
        FROZEN_HEADER = "# frozen_string_literal: true\n"
        BARE_RESCUE_RE = /^(\s*)rescue(\s*\n|\s*=>)/.freeze
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

        def apply
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

        # reduce, not each_with_object: the accumulator here is the rewritten source,
        # so each step must *return* the next value. each_with_object discards the
        # block result and hands the original string back every time, which silently
        # reduced every transform to a no-op.
        def apply_transforms(src, transforms)
          transforms.reduce(src) do |current, transform|
            transform_labels = @transforms.dup
            candidate = send(transform, current)
            next candidate unless ruby? && candidate != current && parses?(current) && !parses?(candidate)

            # Transform turned valid Ruby into unparseable Ruby — a line-heuristic misfire on a
            # multi-line construct. Discard it (and any label it recorded); keep the prior source.
            @transforms.replace(transform_labels)
            current
          end
        end

        def parses?(src) = !Prism.parse(src).failure?

        def publish_and_write(out)
          write_back(out)
          @bus&.publish("ast_fixer:transform", path: @path, transforms: @transforms)
        end

        # Ruby only honors the magic comment on line 1, or line 2 when line 1 is
        # a shebang -- start_with?(FROZEN_HEADER) alone misses that second case
        # and re-inserted a duplicate on every fix cycle for every shebang'd
        # script (confirmed: several tools/*.rb accreted 2, then 3 copies).
        def add_frozen_header(src)
          lines = src.lines
          return src if lines.first(2).any? { |l| l.strip == FROZEN_HEADER.strip }

          if src.start_with?("#!")
            lines.insert(1, FROZEN_HEADER)
            @transforms << :frozen_string_literal
            lines.join
          else
            @transforms << :frozen_string_literal
            FROZEN_HEADER + "\n" + src.lstrip
          end
        end

        def fix_bare_rescue(src)
          result = Prism.parse(src)
          return src unless result.success?

          bare_lines = bare_rescue_lines(result.value)
          return src if bare_lines.empty?

          lines = src.lines
          bare_lines.each do |lineno|
            line_index = lineno - 1
            next unless line_index < lines.size

            lines[line_index] = lines[line_index].sub(/\brescue\b(?!\s+\w)/, "rescue StandardError")
          end
          @transforms << :bare_rescue
          lines.join
        end

        # `= NULL` -> `IS NULL`, in SQL and nowhere else.
        #
        # This ran case-insensitively over every file it was handed, so it also
        # matched JavaScript and Ruby, where `= null` is ordinary assignment.
        # It rewrote web/app/views/chat/index.html.erb's boot script from
        #
        #   var fired=false,timer=null,fallback=null,...
        # to
        #   var fired=false,timerIS NULL,fallbackIS NULL,...
        #
        # — five sites in one file, welded to the identifier because there is no
        # space before the `=`, leaving the face's boot script unparseable. An
        # autofixer that silently breaks the file it is repairing is worse than
        # one that does nothing, so this now refuses anything it cannot show is
        # SQL: uppercase NULL (the SQL convention; JS and Ruby write `null`/`nil`)
        # on a line that also carries a SQL keyword.
        SQL_LINE = /\b(SELECT|INSERT|UPDATE|DELETE|WHERE|FROM|JOIN|HAVING|AND|OR|SET)\b/
        SQL_PATH = /\.(sql|erb\.sql)\z/

        def normalise_null_comparison(src)
          return src if @path.to_s.include?("/review/scan/")

          changed = false
          out = src.lines.map do |line|
            next line unless @path.to_s.match?(SQL_PATH) || line.match?(SQL_LINE)

            line.gsub(/(?<![<>!])=\s*NULL\b/) { changed = true; "IS NULL" }
                .gsub(/!=\s*NULL\b/) { changed = true; "IS NOT NULL" }
                .gsub(/<>\s*NULL\b/) { changed = true; "IS NOT NULL" }
          end.join
          @transforms << :null_comparison if changed
          out
        end

        def bare_rescue_lines(node, lines = [])
          return lines unless node.is_a?(Prism::Node)

          if node.is_a?(Prism::RescueNode) && (node.exceptions.nil? || node.exceptions.empty?)
            lines << node.location.start_line
          end
          node.child_nodes.compact.each { |child| bare_rescue_lines(child, lines) }
          lines
        end

        def expand_tabs(src)
          return src unless src.include?("\t")

          out = src.gsub("\t", "  ")
          @transforms << :expand_tabs if out != src
          out
        end

        def ensure_final_newline(src)
          return src if src.empty? || src.end_with?("\n")

          @transforms << :final_newline
          src + "\n"
        end

        def collapse_blank_lines(src)
          out = src.gsub(/(\n\n)\n+/, "\\1")
          @transforms << :collapse_blank_lines if out != src
          out
        end

        def strip_trailing_whitespace(src)
          out = src.gsub(/[ \t]+(?=\n|\z)/, "")
          @transforms << :trailing_whitespace if out != src
          out
        end

        SINGLE_LINE_MUTABLE_CONST_RE = /
          ^\s*[A-Z][A-Z_]*\s*=\s*
          (?:
            [\[{][^\n]*[\]}]
            |%w\[[^\n]*\]
            |%i\[[^\n]*\]
          )
          (?<!\.freeze)\s*$
        /x.freeze

        def freeze_mutable_constants(src)
          changed = false
          out = src.lines.map do |line|
            next line unless line.match?(SINGLE_LINE_MUTABLE_CONST_RE)

            changed = true
            line.chomp.rstrip + ".freeze\n"
          end.join
          @transforms << :freeze_constants if changed
          out
        end

        STRICT_MODE = "set -euo pipefail\n"

        def add_strict_mode(src)
          return src if src.include?(STRICT_MODE) || src.include?("set -e")

          lines = src.lines
          shebang_idx = lines.index { |line| line.start_with?("#!") }
          return src unless shebang_idx

          lines.insert(shebang_idx + 1, STRICT_MODE)
          @transforms << :strict_mode
          lines.join
        end

        def ruby? = File.extname(@path).downcase == ".rb"

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
