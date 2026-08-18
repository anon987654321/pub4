# frozen_string_literal: true

require "prism"

module Master
  module Review
    module Scan
      class AstFixer
        # Transforms that need to know the source language's syntax: Ruby magic
        # comments, rescue clauses and constant literals; shell strict mode; SQL
        # NULL comparison. Each is reached only through the matching STRATEGIES
        # predicate, so none of them ever sees a file of another language.
        #
        # Separate from AstFixer's own dispatch, which is language-agnostic: it
        # picks strategies, guards Ruby against unparseable output, and writes
        # the file back.
        module SyntaxTransforms
          FROZEN_HEADER = "# frozen_string_literal: true\n"
          STRICT_MODE = "set -euo pipefail\n"

          SINGLE_LINE_MUTABLE_CONST_RE = /
            ^\s*[A-Z][A-Z_]*\s*=\s*
            (?:
              [\[{][^\n]*[\]}]
              |%w\[[^\n]*\]
              |%i\[[^\n]*\]
            )
            (?<!\.freeze)\s*$
          /x.freeze

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

          private

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

          def bare_rescue_lines(node, lines = [])
            return lines unless node.is_a?(Prism::Node)

            if node.is_a?(Prism::RescueNode) && (node.exceptions.nil? || node.exceptions.empty?)
              lines << node.location.start_line
            end
            node.child_nodes.compact.each { |child| bare_rescue_lines(child, lines) }
            lines
          end

          def freeze_mutable_constants(src)
            changed = false
            lines = src.lines
            out = lines.each_with_index.map do |line, index|
              next line unless line.match?(SINGLE_LINE_MUTABLE_CONST_RE)
              # A leading-dot continuation below means the literal heads a
              # method chain — .freeze there freezes a temporary the chain
              # immediately replaces (OPENBSD/health_check.rb CURL).
              next line if lines[index + 1]&.lstrip&.start_with?(".")

              changed = true
              line.chomp.rstrip + ".freeze\n"
            end.join
            @transforms << :freeze_constants if changed
            out
          end

          def normalise_null_comparison(src)
            return src if @path.to_s.include?("/review/scan/")

            changed = false
            out = src.lines.map do |line|
              next line unless sql_line?(line)

              line.gsub(/(?<![<>!])=\s*NULL\b/) { changed = true; "IS NULL" }
                  .gsub(/!=\s*NULL\b/) { changed = true; "IS NOT NULL" }
                  .gsub(/<>\s*NULL\b/) { changed = true; "IS NOT NULL" }
            end.join
            @transforms << :null_comparison if changed
            out
          end

          # In a Ruby file, a line that looks like SQL is a string literal — a
          # test fixture, a query-builder argument, or documentation — and
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
          def sql_line?(line)
            @path.to_s.match?(SQL_PATH) || (!ruby? && line.match?(SQL_LINE))
          end

          def add_strict_mode(src)
            return src if src.include?(STRICT_MODE) || src.include?("set -e")

            lines = src.lines
            shebang_idx = lines.index { |line| line.start_with?("#!") }
            return src unless shebang_idx
            # The rule is STRICT_MODE_ZSH. sh and ksh scripts written to
            # tolerate failure (cron drains, uptime checks) change behaviour
            # under -e, and pipefail is not portable sh — the shebang, not the
            # extension, says which shell this is.
            return src unless lines[shebang_idx].match?(/\bzsh\b/)

            lines.insert(shebang_idx + 1, STRICT_MODE)
            @transforms << :strict_mode
            lines.join
          end
        end
      end
    end
  end
end
