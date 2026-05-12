# frozen_string_literal: true

require "prism"

module Master
  module Judge
  module Scan
    module Rules
      class NestingDepthRule < Rule
        DEFAULT_DEPTH = 2
        NESTING_NODES = %i[
          visit_if_node visit_unless_node visit_case_node visit_case_match_node
          visit_while_node visit_until_node visit_for_node
        ].freeze

        def initialize
          super
          @threshold   = Master::Ground::Axioms.new.thresholds.dig("method", "max_nesting") || DEFAULT_DEPTH
          @id          = "nesting_depth"
          @description = "Nesting deeper than #{@threshold} — use guard clauses to flatten"
          @severity    = :warning
          @axiom_tags  = %i[GUARD_CLAUSES_FIRST KISS]
        end

        def check_ast(ast, _code, path:)
          return [] unless path.end_with?(".rb")
          visitor = Visitor.new(@threshold)
          ast.accept(visitor)
          visitor.findings.map do |line, depth|
            finding(line:, message: "nesting depth #{depth} exceeds #{@threshold} — extract method or add guard clause")
          end
        end

        class Visitor < Prism::Visitor
          attr_reader :findings

          def initialize(threshold)
            super()
            @threshold = threshold
            @findings = []
          end

          def visit_def_node(node)
            counter = DepthCounter.new
            node.body&.accept(counter)
            @findings << [node.location.start_line, counter.max] if counter.max > @threshold
            super
          end
        end

        class DepthCounter < Prism::Visitor
          attr_reader :max

          def initialize
            super
            @depth = 0
            @max = 0
          end

          NESTING_NODES.each do |m|
            define_method(m) do |node|
              @depth += 1
              @max = @depth if @depth > @max
              super(node)
              @depth -= 1
            end
          end

          def visit_def_node(_node) = nil
          def visit_class_node(_node) = nil
          def visit_module_node(_node) = nil
        end
      end
    end
  end
  end
end
