# frozen_string_literal: true

require "prism"

module Master
  module Scan
    module Rules
      class NestingDepthRule < Rule
        DEFAULT_DEPTH = 2

        def initialize
          super
          @threshold   = Master::Axioms.new.thresholds.dig("method", "max_nesting") || DEFAULT_DEPTH
          @id          = "nesting_depth"
          @description = "Nesting deeper than #{@threshold} — use guard clauses to flatten"
          @severity    = :warning
          @axiom_tags  = [:GUARD_CLAUSES_FIRST]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          result = Prism.parse(code)
          return [] unless result.success?

          visitor = NestingVisitor.new(@threshold)
          visitor.visit(result.value)
          visitor.violations.map do |line, depth|
            finding(
              line:,
              message: "nesting depth #{depth} exceeds #{@threshold} — extract method or add guard clause"
            )
          end
        end

        class NestingVisitor < Prism::Visitor
          attr_reader :violations

          def initialize(threshold)
            super()
            @threshold  = threshold
            @violations = []
            @in_method  = 0
            @depth      = 0
            @reported   = false
          end

          def visit_def_node(node)
            saved = [@in_method, @depth, @reported]
            @in_method += 1
            @depth      = 0
            @reported   = false
            super
            @in_method, @depth, @reported = saved
          end

          %i[
            visit_if_node visit_unless_node visit_case_node visit_case_match_node
            visit_while_node visit_until_node visit_for_node visit_begin_node
          ].each do |m|
            define_method(m) do |node|
              if @in_method.positive?
                @depth += 1
                if @depth > @threshold && !@reported
                  @violations << [node.location.start_line, @depth]
                  @reported = true
                end
                super(node)
                @depth -= 1
                @reported = false if @depth <= @threshold
              else
                super(node)
              end
            end
          end
        end
      end
    end
  end
end
