# frozen_string_literal: true

module Master
  module Review
    class ReviewCrew
      class ArchitectureAgent < BaseAgent
        def initialize(root:, code_index: nil, reference_graph: nil)
          super(name: "ArchitectureAgent")
          @root = root
          @code_index = code_index
          @reference_graph = reference_graph
          @cycle_reported = false
        end

        def analyze(code, file_path)
          check_many_public_methods(code, file_path)
          check_ghost_smell(code, file_path)
          check_cyclic_dependency(code, file_path)
          check_message_chain(code, file_path)
          findings
        end

        private

        def check_many_public_methods(code, file_path)
          count = code.each_line.count
          return unless count > 10 && code.scan(/^\s*def\s+/).size > 10

          add_finding(
            severity: :warning,
            category: :architecture,
            message: "many public methods detected",
            line: 1,
            suggestion: "split into smaller collaborating objects",
            file_path:,
          )
        end

        def check_ghost_smell(code, file_path)
          return unless ghost_smell?(code)

          add_finding(
            severity: :warning,
            category: :architecture,
            message: "ghost smell detected: guard clause may be hiding a missing abstraction",
            line: 1,
            suggestion: "look for repeated branching that wants a shared object or explicit policy",
            file_path:,
          )
        end

        def check_cyclic_dependency(_code, file_path)
          return if @cycle_reported

          cycle = detect_cycle
          return unless cycle

          add_finding(
            severity: :error,
            category: :architecture,
            message: "cyclic dependency detected: #{cycle.join(' -> ')}",
            line: 1,
            suggestion: "break the require chain by extracting shared code into a lower-level module",
            file_path:,
          )
          @cycle_reported = true
        end

        def check_message_chain(code, file_path)
          return unless code.match?(/\b[a-z_]+(\.[a-z_]+){3,}\b/)

          add_finding(
            severity: :warning,
            category: :architecture,
            message: "message chain detected",
            line: 1,
            suggestion: "introduce a local variable or delegation",
            file_path:,
          )
        end

        def detect_cycle
          return unless @reference_graph

          graph = @reference_graph.build
          edges = Array(graph[:edges]).select { |edge| edge[:type].to_s == "require" }
          adjacency = Hash.new { |hash, key| hash[key] = [] }
          edges.each { |edge| adjacency[edge[:from]] << edge[:to] }

          visited = {}
          stack = []

          adjacency.keys.each do |node|
            cycle = visit_node(node, adjacency:, visited:, stack:)
            return cycle if cycle
          end
          nil
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "ArchitectureAgent.detect_cycle")
          nil
        end

        def ghost_smell?(code)
          return false unless code.match?(/\breturn\s+(?:if|unless)\b/)

          method_count = code.scan(/^\s*def\s+/).size
          branch_count = code.scan(/^\s*(if|unless|case|when)\b/).size
          repeated_guards = code.scan(/\breturn\s+(?:if|unless)\b/).size
          method_count >= 4 && branch_count >= 4 && repeated_guards >= 2
        end

        def visit_node(node, adjacency:, visited:, stack:)
          return if visited[node]
          visited[node] = true
          stack << node

          Array(adjacency[node]).each do |child|
            if stack.include?(child)
              idx = stack.index(child) || 0
              return stack[idx..] + [child]
            end
            cycle = visit_node(child, adjacency:, visited:, stack:)
            return cycle if cycle
          end

          stack.pop
          nil
        end
      end
    end
  end
end
