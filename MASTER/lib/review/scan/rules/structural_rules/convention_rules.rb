# frozen_string_literal: true

require "prism"

module Master
  module Review
    module Scan
      module Rules
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
            indexed_lines = src.lines.each_with_index
            indexed_lines.filter_map do |line, i|
              finding(line: i + 1, message:) if line.match?(pattern)
            end
          end
        end

        # B08 CYCLOMATIC_COMPLEXITY — methods with cyclomatic complexity > 10.
        class CyclomaticComplexityRule < Rule
          MAX_CC = 10
          CC_NODES = [
            Prism::IfNode, Prism::UnlessNode, Prism::WhileNode, Prism::UntilNode,
            Prism::ForNode, Prism::WhenNode, Prism::RescueNode, Prism::AndNode,
            Prism::OrNode
          ].freeze

          def initialize
            super()
            @id = "CYCLOMATIC_COMPLEXITY"
            @description = "cyclomatic complexity under 10 per method"
            @severity = :warning
            @rule_tags = %i[LINEARITY SMALL_PARTS]
            @auto_fix = false
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

          def check_ast(ast, code, path:)
            return [] unless ast

            lines = code.lines
            findings = []
            visit(ast) { |node| findings << def_node_finding(node, lines) if node.is_a?(Prism::DefNode) }
            findings.compact
          end

          private

          def def_node_finding(node, lines)
            method_lines = lines[(node.location.start_line - 1)...node.location.end_line].join
            branch_count = branch_dispatch_count(method_lines)
            if branch_count >= BRANCH_THRESHOLD
              finding(
                line: node.location.start_line,
                message: "Strategy opportunity in #{node.name}: #{branch_count} dispatch branches — extract named handlers",
              )
            elsif pipeline_step_count(method_lines) >= PIPELINE_STEP_THRESHOLD
              finding(
                line: node.location.start_line,
                message: "Pipeline opportunity in #{node.name}: sequential transformations can be named stages",
              )
            end
          end

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
      end
    end
  end
end
