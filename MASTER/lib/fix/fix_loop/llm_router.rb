# frozen_string_literal: true

module Master
  module Fix
    class FixLoop
      class LlmRouter
        def initialize(agent)
          @agent = agent
        end

        # Only the model this pass would actually dispatch to matters -- an
        # unrelated fallback model's open breaker (e.g. a flaky free-tier
        # endpoint) must not silently skip the whole LLM stage when the
        # model in use is healthy.
        def circuit_open?
          !open_breakers.empty?
        end

        def open_breakers
          model_id = current_model
          return [] unless model_id

          registry = @agent.circuit_breaker
          registry.respond_to?(:open?) && registry.open?(model_id) ? [model_id] : []
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "LlmRouter.open_breakers")
          []
        end

        private

        def current_model
          @agent.respond_to?(:model) ? @agent.model : nil
        end
      end
    end
  end
end
