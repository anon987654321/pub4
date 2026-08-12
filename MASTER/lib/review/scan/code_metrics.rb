# frozen_string_literal: true

module Master
  module Review
    module Scan
      # How this repo counts code. One implementation, because there were three.
      #
      # `rake lint:spine` and `tools/ratchets.rb` each carried their own copy of
      # the non-blank-non-comment line count — for the same ratchet, reported in
      # the same table. `SmallFunctionsRule` carried a third for method bodies.
      # They happened to agree; nothing made them.
      #
      # Counting is also where a throwaway script is most likely to be quietly
      # wrong. A hand-rolled method-length counter that treats `def x = expr`
      # as running to the next `end` reports a tightly-factored file as sprawling,
      # and the number looks plausible enough to reason from. tools/fixtures/
      # declares the right answers for cases like that and `rake lint:instruments`
      # holds this module to them.
      module CodeMetrics
        module_function

        # Non-blank, non-comment. A trailing comment on a code line still counts,
        # because that line carries code.
        def code_line?(line)
          stripped = line.strip
          !stripped.empty? && !stripped.start_with?("#")
        end

        def code_lines(source)
          source.to_s.lines.count { |line| code_line?(line) }
        end

        def code_lines_in(dir)
          Dir.glob(File.join(dir, "**", "*.rb")).sum { |file| code_lines(File.read(file)) }
        end

        # A method's body only: between `def` and its `end`, blank lines and
        # whole-line comments excluded.
        #
        # The span version counted comments toward method length, which
        # contradicts the rule's own description — that is about how much logic a
        # method holds, not how well it is explained. Cli::TurnRouter.call was
        # reported at 22 lines while holding 10 of code and 8 of comment, so the
        # only way to pass was to delete the explanation.
        #
        # An endless method (`def x = expr`) has start_line == end_line and
        # therefore a body of zero lines, which is the case a regex counter gets
        # wrong by scanning forward to the next `end`.
        def method_code_lines(node, lines)
          first = node.location.start_line
          last = node.location.end_line
          return 0 if last <= first

          (lines[first...(last - 1)] || []).count { |line| code_line?(line) }
        end

        # Defs before the first `private`/`protected` in a class body.
        def public_method_count(class_node)
          return 0 unless class_node.respond_to?(:body) && class_node.body

          count = 0
          class_node.body.child_nodes.compact.each do |node|
            break if node.is_a?(Prism::CallNode) && %w[private protected].include?(node.name.to_s)

            count += 1 if node.is_a?(Prism::DefNode)
          end
          count
        end
      end
    end
  end
end
