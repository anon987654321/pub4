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

        # Lines that exist only because Zeitwerk maps a path to a constant.
        #
        # `module Master` / `module Ground` / `module Policy` wrapping one nested
        # module carry no implementation; the loader requires them and the file
        # would not resolve without them. Counting them made every structural
        # improvement cost two lines per file, so lint:spine and lint:cohesion
        # pulled against each other and cohesion lost by default — three rounds
        # of regrouping were paid for by luck, then by the last orphan in lib/,
        # then by a budget raise.
        #
        # Only `module`, and only when its body is exactly one module or class.
        # A module holding a constant, a method, or two children is doing work
        # and counts. A `class` wrapping a class is a design choice nothing
        # forced, and counts too.
        def namespace_lines(source)
          require "prism"
          result = Prism.parse(source.to_s)
          return 0 unless result.success?

          count_namespaces(result.value)
        end

        def count_namespaces(node)
          return 0 unless node.respond_to?(:child_nodes)

          own = pure_namespace?(node) ? 2 : 0
          node.child_nodes.compact.sum(own) { |child| count_namespaces(child) }
        end

        # Two lines: the `module` and its `end`.
        def pure_namespace?(node)
          return false unless node.is_a?(Prism::ModuleNode)

          statements = node.body
          return false unless statements.is_a?(Prism::StatementsNode)
          return false unless statements.body.size == 1

          statements.body.first.is_a?(Prism::ModuleNode) || statements.body.first.is_a?(Prism::ClassNode)
        end

        # What lint:spine bounds: code minus the loader's ceremony.
        def body_lines(source) = code_lines(source) - namespace_lines(source)

        def body_lines_in(dir)
          Dir.glob(File.join(dir, "**", "*.rb")).sum { |file| body_lines(File.read(file)) }
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
        # `private` does not touch `def self.x`, so a class whose internals are all
        # class methods counted as fully public. Core::Constitution read as 16
        # public methods when three are its API and thirteen are rule factories
        # only it calls — ABSTRACTION was measuring the idiom, not the surface.
        # private_class_method names its methods instead of marking a position,
        # so they are collected and subtracted rather than stopping the walk.
        def public_method_count(class_node)
          return 0 unless class_node.respond_to?(:body) && class_node.body

          nodes = class_node.body.child_nodes.compact
          hidden = private_class_method_names(nodes)
          count = 0
          nodes.each do |node|
            break if node.is_a?(Prism::CallNode) && %w[private protected].include?(node.name.to_s)

            count += 1 if node.is_a?(Prism::DefNode) && !hidden.include?(node.name.to_s)
          end
          count
        end

        def private_class_method_names(nodes)
          nodes.grep(Prism::CallNode)
               .select { |node| node.name.to_s == "private_class_method" }
               .flat_map { |node| node.arguments&.arguments.to_a.grep(Prism::SymbolNode).map(&:unescaped) }
        end
      end
    end
  end
end
