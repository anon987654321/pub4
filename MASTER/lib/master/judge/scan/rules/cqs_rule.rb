# frozen_string_literal: true

require "prism"

module Master
  module Judge
  module Scan
    module Rules
      # CqsRule — Command/Query Separation. A method named like a query
      # (get_*, find_*, fetch_*, etc.) must not mutate state in its body.
      class CqsRule < Rule
        QUERY_PREFIXES = %w[get_ find_ fetch_ load_ read_ list_ show_ describe_].freeze
        MUTATING_CALLS = %i[
          save save! update update! update_attribute update_attribute!
          update_columns update_column delete destroy destroy! create create!
          write write! push pop shift unshift clear concat
        ].freeze

        def initialize
          super
          @id          = "cqs"
          @description = "Command/Query Separation — queries must not mutate state"
          @severity    = :warning
          @rule_tags  = [:CQS]
        end

        def check_ast(ast, _code, path:)
          return [] unless path.end_with?(".rb")
          visitor = Visitor.new
          ast.accept(visitor)
          visitor.findings.map do |line, name|
            finding(line:, message: "query method `#{name}` mutates state — split into command + query")
          end
        end

        class Visitor < Prism::Visitor
          attr_reader :findings

          def initialize
            super
            @findings = []
          end

          def visit_def_node(node)
            name = node.name.to_s
            if QUERY_PREFIXES.any? { |p| name.start_with?(p) } && mutates?(node.body)
              @findings << [node.location.start_line, name]
            end
            super
          end

          private

          def mutates?(body)
            return false if body.nil?
            finder = MutationFinder.new
            body.accept(finder)
            finder.mutating?
          end
        end

        class MutationFinder < Prism::Visitor
          def initialize
            super
            @found = false
          end

          def mutating? = @found

          def visit_call_node(node)
            @found = true if MUTATING_CALLS.include?(node.name)
            super
          end

          def visit_instance_variable_write_node(_node)
            @found = true
            super
          end

          def visit_instance_variable_operator_write_node(_node)
            @found = true
            super
          end

          def visit_instance_variable_and_write_node(_node)
            @found = true
            super
          end

          def visit_instance_variable_or_write_node(_node)
            @found = true
            super
          end
        end
      end
    end
  end
  end
end
