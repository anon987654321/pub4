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
        # EACH_WITH_OBJECT (data/rules/line.yml). That rule's lexical detector
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

            if ruby? && candidate != current && parses?(current) && !parses?(candidate)
              # Transform turned valid Ruby into unparseable Ruby — a line-heuristic
              # misfire on a multi-line construct. Discard it (and any label it
              # recorded); keep the prior source.
              @transforms.replace(transform_labels)
              next
            end

            current = candidate
          end
          current
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
            # In a Ruby file, a line that looks like SQL is a string literal —
            # a test fixture, a query-builder argument, or documentation — and
            # rewriting inside one on a line-level regex is guessing at content
            # the parser could have told us about.
            #
            # It has now guessed wrong twice. First it welded a JavaScript
            # `timer=null` into `timerIS NULL` across five sites of the face's
            # boot script (84371b070). Then, with the line heuristic added to
            # narrow it, it rewrote this very rule's own fixture in
            # test_ast_fixer_safety.rb: `deleted_at = NULL` became `IS NULL`, so
            # the test fed already-correct SQL and asserted it was correct. A
            # vacuous test, and thirteen sibling transforms broken alongside it.
            #
            # The fixer's source was already excluded above; its tests were not,
            # and a test for a repair rule contains by construction exactly the
            # input the rule repairs. Excluding Ruby from the line heuristic
            # covers that case and every future fixture like it, without a list
            # of filenames to keep current. A .sql path still always repairs.
            sql_here = @path.to_s.match?(SQL_PATH) || (!ruby? && line.match?(SQL_LINE))
            next line unless sql_here

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
