# frozen_string_literal: true

require "prism"

module Master
  module Judge
  module Scan
    module Rules
      # Too many constructor args signal a god object; callers can't reason
      # about what matters. Reads max_params from rules.yml.
      class ArityRule < Rule
        DEFAULT_MAX = 3

        def initialize
          super
          @max_params  = Master::Ground::Rules.new.thresholds.dig("method", "max_params") || DEFAULT_MAX
          @id          = "arity"
          @description = "initialize with > #{@max_params} args — extract a context struct or config object"
          @severity    = :warning
          @rule_tags  = %i[DECOUPLE ONE_JOB KISS]
        end

        def check_ast(ast, _code, path:)
          return [] unless path.end_with?(".rb")
          visitor = Visitor.new(@max_params)
          ast.accept(visitor)
          visitor.findings.map do |line, count|
            finding(line:, 
message: "initialize takes #{count} args (max #{@max_params}) — extract AgentContext or Config struct")
          end
        end

        class Visitor < Prism::Visitor
          attr_reader :findings

          def initialize(max)
            super()
            @max = max
            @findings = []
          end

          def visit_def_node(node)
            if node.name == :initialize
              count = param_count(node.parameters)
              @findings << [node.location.start_line, count] if count > @max
            end
            super
          end

          private

          def param_count(params)
            return 0 if params.nil?
            params.requireds.size +
              params.optionals.size +
              params.posts.size +
              params.keywords.size +
              (params.rest ? 1 : 0) +
              (params.keyword_rest ? 1 : 0) +
              (params.block ? 1 : 0)
          end
        end
      end
    end
  end
  end
end
