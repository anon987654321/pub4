# frozen_string_literal: true

require "prism"

module Master
  module Judge
    module Scan
      module Rules
      # Structural rules use Prism AST rather than line-by-line regex.
      # Each implements check_ast(ast, code, path:) for scanner integration.
      # All also implement check(code, path:) as fallback for non-Ruby files.

      # B01 SMALL_FILES — files over 300 lines (detect_structural: file_silhouette).
        class SmallFilesRule < Rule
          LIMIT = 300

          def initialize
            super()
            @id = "SMALL_FILES"
            @description = "files under 300 lines"
            @severity = :warning
            @rule_tags = %i[SMALL_PARTS]
            @auto_fix = false
          end

          def check(code, path:)
            count = code.lines.size
            return [] if count <= LIMIT
            [finding(line: 1, message: "file #{count} lines (limit #{LIMIT}) — split at module boundaries")]
          end
        end

      # B02 SMALL_FUNCTIONS — methods over 20 lines via Prism (detect_structural: long_method).
        class SmallFunctionsRule < Rule
          IDEAL = 10
          MAX = 20

          def initialize
            super()
            @id = "SMALL_FUNCTIONS"
            @description = "methods under 10 lines ideal, max 20"
            @severity = :warning
            @rule_tags = %i[SMALL_PARTS]
            @auto_fix = false
          end

          def check(code, path:)
            return [] unless path.to_s.end_with?(".rb", ".rake")
            check_ast(Prism.parse(code).value, code, path:)
          rescue StandardError
            []
          end

          def check_ast(ast, _code, path:)
            return [] unless ast
            findings = []
            visit(ast) do |node|
              next unless node.is_a?(Prism::DefNode)
              len = node.location.end_line - node.location.start_line
              next if len <= MAX
              name = node.name
              findings << finding(line: node.location.start_line, message: "method #{name} is #{len} lines (max #{MAX}) — extract helpers")
            end
            findings
          end

          private

          def visit(node, &block)
            return unless node.respond_to?(:child_nodes)
            block.call(node)
            node.child_nodes.compact.each { |c| visit(c, &block) }
          end
        end

      # B03 NO_GOD_CLASS — class with >10 public methods (detect_structural: god_class).
        class GodClassRule < Rule
          METHOD_LIMIT = 10
          LINE_LIMIT = 300

          def initialize
            super()
            @id = "NO_GOD_CLASS"
            @description = "no god classes"
            @severity = :error
            @rule_tags = %i[SOLID SRP]
            @auto_fix = false
          end

          def check(code, path:)
            return [] unless path.to_s.end_with?(".rb", ".rake")
            check_ast(Prism.parse(code).value, code, path:)
          rescue StandardError
            []
          end

          def check_ast(ast, code, path:)
            return [] unless ast
            findings = []
            visit(ast) do |node|
              next unless node.is_a?(Prism::ClassNode)
              public_defs = count_public_methods(node)
              line_count = node.location.end_line - node.location.start_line
              if public_defs > METHOD_LIMIT
                findings << finding(
                  line: node.location.start_line,
                  message: "god class #{node.constant_path.slice} has #{public_defs} public methods (max #{METHOD_LIMIT}) — decompose"
                )
              elsif line_count > LINE_LIMIT
                findings << finding(
                  line: node.location.start_line,
                  message: "god class #{node.constant_path.slice} is #{line_count} lines — split at responsibility boundaries"
                )
              end
            end
            findings
          end

          private

          def visit(node, &block)
            return unless node.respond_to?(:child_nodes)
            block.call(node)
            node.child_nodes.compact.each { |c| visit(c, &block) }
          end

          def count_public_methods(class_node)
            count = 0
            in_private = false
            return count unless class_node.respond_to?(:body) && class_node.body
            class_node.body.child_nodes.compact.each do |node|
              if node.is_a?(Prism::CallNode) && %w[private protected].include?(node.name.to_s)
                in_private = true
              end
              count += 1 if !in_private && node.is_a?(Prism::DefNode)
            end
            count
          end
        end

      # B07 NESTING_DEPTH — nesting deeper than 4 levels (detect_structural: nesting_depth).
        class NestingDepthRule < Rule
          MAX_DEPTH = 4

          NESTING_TYPES = [
            Prism::ModuleNode, Prism::ClassNode, Prism::DefNode,
            Prism::IfNode, Prism::UnlessNode, Prism::WhileNode,
            Prism::UntilNode, Prism::ForNode, Prism::CaseNode,
            Prism::BlockNode,
          ].freeze

          def initialize
            super()
            @id = "NESTING_DEPTH"
            @description = "nesting depth under 4"
            @severity = :warning
            @rule_tags = %i[LINEARITY]
            @auto_fix = false
          end

          def check(code, path:)
            return [] unless path.to_s.end_with?(".rb", ".rake")
            check_ast(Prism.parse(code).value, code, path:)
          rescue StandardError
            []
          end

          def check_ast(ast, _code, path:)
            return [] unless ast
            deep = []
            scan_depth(ast, 0, deep)
            deep.map { |line| finding(line:, message: "nesting depth exceeds #{MAX_DEPTH} — flatten with guard clauses or extract methods") }
          end

          private

          def scan_depth(node, depth, violations)
            return unless node.respond_to?(:child_nodes)
            new_depth = NESTING_TYPES.include?(node.class) ? depth + 1 : depth
            if new_depth > MAX_DEPTH && violations.none? { |l| (l - node.location.start_line).abs < 3 }
              violations << node.location.start_line
            end
            node.child_nodes.compact.each { |c| scan_depth(c, new_depth, violations) }
          rescue StandardError
            nil
          end
        end

      end
    end
  end
end
