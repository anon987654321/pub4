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

      # B04 CQS — method that both mutates state and returns a meaningful value.
        class CqsRule < Rule
          def initialize
            super()
            @id = "CQS"
            @description = "command-query separation — mutate OR return, not both"
            @severity = :warning
            @rule_tags = %i[CQS CLEAN_CODE]
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
              body = node.body
              next unless body
              mutates = body_contains?(body, Prism::InstanceVariableWriteNode, Prism::InstanceVariableOperatorWriteNode)
              returns_value = body_has_explicit_return?(body)
              if mutates && returns_value
                findings << finding(line: node.location.start_line,
                  message: "method #{node.name} mutates state and returns a value — split into command and query")
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

          def body_contains?(node, *types)
            return false unless node.respond_to?(:child_nodes)
            types.any? { |t| node.is_a?(t) } ||
              node.child_nodes.compact.any? { |c| body_contains?(c, *types) }
          end

          def body_has_explicit_return?(node)
            return false unless node.respond_to?(:child_nodes)
            return true if node.is_a?(Prism::ReturnNode) && node.arguments&.arguments&.any?
            node.child_nodes.compact.any? { |c| body_has_explicit_return?(c) }
          end
        end

      # B05 FILE_LAYOUT — Ruby file order: frozen → require → module → class → public → private.
        class FileLayoutRule < Rule
          def initialize
            super()
            @id = "FILE_LAYOUT"
            @description = "frozen header → requires → module/class → public → private"
            @severity = :info
            @rule_tags = %i[PROXIMITY CONVENTION]
            @auto_fix = false
          end

          def check(code, path:)
            return [] unless path.to_s.end_with?(".rb", ".rake")
            findings = []
            lines = code.lines
            first_non_comment = lines.find_index { |l| !l.match?(/^\s*#|^\s*$/) }
            return [] unless first_non_comment
            unless lines.first&.include?("frozen_string_literal")
              findings << finding(line: 1, message: "missing # frozen_string_literal: true as first line")
            end
            private_idx = lines.find_index { |l| l.match?(/^\s+private\s*$|^\s+private\b/) }
            if private_idx
              public_def_after_private = lines[private_idx..].each_with_index.find do |l, i|
                l.match?(/^\s+def (?!self\.)/) && !l.match?(/^\s+def (?:initialize|to_s|inspect)\b/)
              end
              if public_def_after_private
                idx = private_idx + public_def_after_private[1] + 1
                findings << finding(line: idx, message: "public method def after private marker — move above private")
              end
            end
            findings
          end
        end

      # B06 EXPLICIT — implicit requires, magic coupling, method_missing without respond_to_missing?.
        class ExplicitRule < Rule
          def initialize
            super()
            @id = "EXPLICIT"
            @description = "no implicit requires or magic coupling"
            @severity = :warning
            @rule_tags = %i[EXPLICIT CONVENTION]
            @auto_fix = false
          end

          def check(code, path:)
            return [] unless path.to_s.end_with?(".rb", ".rake")
            findings = []
            findings.concat(scan_lines(code, /\bmethod_missing\b/, message: "method_missing without respond_to_missing? — add respond_to_missing?")) \
              if code.include?("method_missing") && !code.include?("respond_to_missing?")
            findings.concat(scan_lines(code, /\bconst_missing\b/, message: "const_missing — prefer explicit require"))
            findings.concat(scan_lines(code, /\bautoload\b/, message: "autoload — prefer explicit require_relative"))
            findings
          end

          private

          def scan_lines(src, pattern, message:)
            src.lines.each_with_index.filter_map do |line, i|
              finding(line: i + 1, message: message) if line.match?(pattern)
            end
          end
        end

      # B08 CYCLOMATIC_COMPLEXITY — methods with cyclomatic complexity > 10.
        class CyclomaticComplexityRule < Rule
          MAX_CC = 10
          CC_NODES = [
            Prism::IfNode, Prism::UnlessNode, Prism::WhileNode, Prism::UntilNode,
            Prism::ForNode, Prism::WhenNode, Prism::RescueNode, Prism::AndNode,
            Prism::OrNode,
          ].freeze

          def initialize
            super()
            @id = "CYCLOMATIC_COMPLEXITY"
            @description = "cyclomatic complexity under 10 per method"
            @severity = :warning
            @rule_tags = %i[LINEARITY SMALL_PARTS]
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
              cc = 1 + count_cc_nodes(node)
              next if cc <= MAX_CC
              findings << finding(line: node.location.start_line,
                message: "method #{node.name} has cyclomatic complexity #{cc} (max #{MAX_CC}) — extract branches")
            end
            findings
          end

          private

          def visit(node, &block)
            return unless node.respond_to?(:child_nodes)
            block.call(node)
            node.child_nodes.compact.each { |c| visit(c, &block) }
          end

          def count_cc_nodes(node)
            return 0 unless node.respond_to?(:child_nodes)
            own = CC_NODES.include?(node.class) ? 1 : 0
            own + node.child_nodes.compact.sum { |c| count_cc_nodes(c) }
          end
        end

      # B09 PATTERN_EXTRACTION — code close to a named design pattern.
        class PatternExtractionRule < Rule
          BRANCH_THRESHOLD = 3
          PIPELINE_STEP_THRESHOLD = 4

          def initialize
            super()
            @id = "PATTERN_EXTRACTION"
            @description = "file is close to a named design pattern"
            @severity = :info
            @rule_tags = %i[DESIGN OPPORTUNITY]
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
            lines = code.lines
            visit(ast) do |node|
              next unless node.is_a?(Prism::DefNode)
              method_lines = lines[(node.location.start_line - 1)...node.location.end_line].join
              branch_count = branch_dispatch_count(method_lines)
              if branch_count >= BRANCH_THRESHOLD
                findings << finding(
                  line: node.location.start_line,
                  message: "Strategy opportunity in #{node.name}: #{branch_count} dispatch branches — extract named handlers"
                )
              elsif pipeline_step_count(method_lines) >= PIPELINE_STEP_THRESHOLD
                findings << finding(
                  line: node.location.start_line,
                  message: "Pipeline opportunity in #{node.name}: sequential transformations can be named stages"
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

          def branch_dispatch_count(src)
            src.lines.count { |line| line.match?(/^\s*(when|elsif)\b/) }
          end

          def pipeline_step_count(src)
            assignments = src.lines.filter_map do |line|
              match = line.match(/^\s*([a-z_]\w*)\s*=\s*(.+)$/)
              [match[1], match[2]] if match
            end
            return 0 if assignments.size < PIPELINE_STEP_THRESHOLD
            assignments.each_cons(PIPELINE_STEP_THRESHOLD).find { |group| chained_assignments?(group) }&.size.to_i
          end

          def chained_assignments?(group)
            names = group.map(&:first)
            return false unless names.uniq.size == names.size
            group.each_cons(2).all? { |left, right| right.last.match?(/\b#{Regexp.escape(left.first)}\b/) }
          end
        end

      # B10 DATA_CLASS — class with only attr_accessor and no real methods.
        class DataClassRule < Rule
          def initialize
            super()
            @id = "DATA_CLASS"
            @description = "data class with no behavior — use Struct or Data"
            @severity = :info
            @rule_tags = %i[SRP SOLID]
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
              next unless node.is_a?(Prism::ClassNode)
              next unless node.body
              children = node.body.child_nodes.compact
              accessor_calls = children.count { |n| n.is_a?(Prism::CallNode) && %w[attr_accessor attr_reader attr_writer].include?(n.name.to_s) }
              real_defs = children.count { |n| n.is_a?(Prism::DefNode) && !%w[initialize to_s inspect].include?(n.name.to_s) }
              next unless accessor_calls >= 2 && real_defs == 0
              findings << finding(line: node.location.start_line,
                message: "#{node.constant_path.slice} has #{accessor_calls} accessors and no behavior — use Struct or Data.define")
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

        StructuralRules = Module.new
      end
    end
  end
end
