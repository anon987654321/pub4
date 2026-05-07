# frozen_string_literal: true

require "prism"

module Master
  module Scan
    module Rules
      class GodClassRule < Rule
        DEFAULT_THRESHOLD = 200

        def initialize
          super
          @threshold   = Master::Axioms.new.thresholds.dig("class", "max_lines") || DEFAULT_THRESHOLD
          @id          = "god_class"
          @description = "Classes over #{@threshold} lines should be split by responsibility"
          @severity    = :warning
          @axiom_tags  = %i[SIMPLEST_WORKS KISS SRP]
        end

        def check_ast(ast, _code, path:)
          return [] unless path.end_with?(".rb")
          visitor = Visitor.new(@threshold)
          ast.accept(visitor)
          visitor.findings.map do |line, name, lines|
            finding(line:, message: "#{name} is #{lines} lines (threshold: #{@threshold}) — split by responsibility")
          end
        end

        class Visitor < Prism::Visitor
          attr_reader :findings

          def initialize(threshold)
            super()
            @threshold = threshold
            @findings = []
          end

          def visit_class_node(node)
            lines = node.location.end_line - node.location.start_line + 1
            if lines > @threshold
              @findings << [node.location.start_line, node.name.to_s, lines]
            end
            super
          end
        end
      end
    end
  end
end
