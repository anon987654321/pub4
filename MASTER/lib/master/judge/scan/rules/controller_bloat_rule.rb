# frozen_string_literal: true

module Master
  module Judge
  module Scan
    module Rules
      class ControllerBloatRule < Rule
        def initialize
          super
          @id = "controller_bloat"
          @description = "Controllers with too many actions are hard to evolve"
          @severity = :warning
          @axiom_tags = %i[COHESION]
        end

        def check(code, path:)
          return [] unless path.include?("/app/controllers/") && path.end_with?(".rb")
          actions = code.scan(/^\s*def\s+\w+/)
          return [] if actions.size <= 7
          [finding(line: 1, message: "controller defines #{actions.size} actions; split by namespace/service")]
        end
      end
    end
  end
  end
end
