# frozen_string_literal: true

module Master
  module Loop
    class FixLoop
      class LlmRouter
        def initialize(agent)
          @agent = agent
        end

        def circuit_open?
          !open_breakers.empty?
        end

        def open_breakers
          @agent.respond_to?(:circuit_breaker) ? Array(@agent.circuit_breaker&.open_models) : []
        rescue StandardError
          []
        end
      end
    end
  end
end
