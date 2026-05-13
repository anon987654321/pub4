# frozen_string_literal: true

require "prism"

module Master
  module Judge
  module Scan
    module Rules
      class BareRescueRule < Rule
        def initialize
          super
          @id          = "bare_rescue"
          @description = "Never use bare rescue -- always specify exception type"
          @severity    = :error
          @rule_tags  = [:FAIL_VISIBLY]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          result = Prism.parse(code)
          return [] unless result.success?

          visitor = BareRescueVisitor.new(self)
          visitor.visit(result.value)
          visitor.findings
        end

        # Allow protected #finding to be called from the visitor.
        def emit(line:, message:)
          finding(line:, message:)
        end

        class BareRescueVisitor < Prism::Visitor
          attr_reader :findings

          def initialize(rule)
            super()
            @rule     = rule
            @findings = []
          end

          def visit_rescue_node(node)
            if node.exceptions.empty?
              @findings << @rule.emit(
                line: node.location.start_line,
                message: "bare rescue: specify exception type (e.g. rescue StandardError)"
              )
            end
            if rescues_exception_class?(node)
              @findings << @rule.emit(
                line: node.location.start_line,
                message: "rescue Exception is too broad: rescue StandardError or a specific class"
              )
            end
            super
          end

          private

          def rescues_exception_class?(node)
            node.exceptions.any? do |exception_node|
              exception_node.is_a?(Prism::ConstantReadNode) && exception_node.name == :Exception
            end
          end
        end
      end
    end
  end
  end
end
