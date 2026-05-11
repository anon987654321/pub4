# frozen_string_literal: true

require "prism"

module Master
  module Scan
    module Rules
      class LongMethodRule < Rule
        DEFAULT_THRESHOLD = 10

        def initialize
          super
          @threshold   = Master::Ground::Axioms.new.thresholds.dig("method", "max_lines") || DEFAULT_THRESHOLD
          @id          = "long_method"
          @description = "Methods over #{@threshold} lines should be extracted"
          @severity    = :warning
          @axiom_tags  = %i[ONE_JOB KISS]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          result = Prism.parse(code)
          return [] unless result.success?

          visitor = MethodVisitor.new(@threshold)
          visitor.visit(result.value)
          visitor.methods_over_threshold.map do |name, line, length|
            finding(
              line:,
              message: "method #{name} is #{length} lines (threshold: #{@threshold}) — extract responsibilities"
            )
          end
        end

        class MethodVisitor < Prism::Visitor
          attr_reader :methods_over_threshold

          def initialize(threshold)
            super()
            @threshold              = threshold
            @methods_over_threshold = []
          end

          def visit_def_node(node)
            length = node.location.end_line - node.location.start_line + 1
            if length > @threshold
              @methods_over_threshold << [node.name.to_s, node.location.start_line, length]
            end
            super
          end
        end
      end
    end
  end
end
