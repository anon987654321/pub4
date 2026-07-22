# frozen_string_literal: true

module Master
  module Fix
    class FixLoop
      class LlmRouter
        def initialize(agent)
          @agent = agent
        end

        # Only genuinely blocked if *every* model this dispatch could fall
        # back to has an open breaker -- an unrelated free-tier model at
        # the front of the chain being down must not skip the whole LLM
        # stage while a healthy fallback (e.g. claude-cli) is still usable.
        def circuit_open?
          !open_breakers.empty?
        end

        def open_breakers
          models = candidate_models
          return [] if models.empty?

          registry = @agent.circuit_breaker
          return [] unless registry.respond_to?(:open?)

          models.all? { |m| registry.open?(m) } ? models : []
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "LlmRouter.open_breakers")
          []
        end

        private

        def candidate_models
          return Array(@agent.candidate_models) if @agent.respond_to?(:candidate_models)

          model = @agent.respond_to?(:model) ? @agent.model : nil
          model ? [model] : []
        end
      end
    end
  end
end
