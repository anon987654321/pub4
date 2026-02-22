# frozen_string_literal: true

module MASTER
  module Stages
    # Stage 4: Route to model via circuit breaker + budget
    class Route
      def call(input)
        if defined?(Logging)
          Logging.dmesg_log("route0", parent: "pipeline0", message: "ENTER route",
                                      level: Logging::ALL_EVENTS)
        end
        # Respect forced model override (model command)
        if LLM.model_forced?
          model = LLM.forced_model
          tier = LLM.classify_tier(model)
        else
          tier = LLM.tier
          model = LLM.select_model(tier)
        end
        return Result.err("All models unavailable.", category: :infrastructure) unless model

        Result.ok(input.merge(model: model, tier: tier))
      end
    end
  end
end
