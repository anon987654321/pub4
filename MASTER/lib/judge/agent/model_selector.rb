# frozen_string_literal: true

module Master
  module Judge
    class Agent
      module ModelSelector
        private

        def routed_models(message = nil)
          return [@config.model] unless @model_router
          task = message ? @model_router.classify_intent(message) : @config.task_type.to_sym
          chain = @model_router.fallback_chain(task_type: task)
          bias = @homeostat&.model_tier_bias
          return cheap_first(chain) if bias == :cheap
          return strong_first(chain) if bias == :strong
          chain
        rescue StandardError => e
          @bus&.publish("llm:route_error", error: e.message)
          [@config.model]
        end

        def cheap_first(chain)
          cheap = chain.select { |m| @model_router.tier_for_model(m) == "cheap" }
          rest  = chain.reject { |m| @model_router.tier_for_model(m) == "cheap" }
          cheap.empty? ? chain : (cheap + rest)
        end

        def strong_first(chain)
          strong = chain.select { |m| @model_router.tier_for_model(m) == "strong" }
          rest   = chain.reject { |m| @model_router.tier_for_model(m) == "strong" }
          strong.empty? ? chain : (strong + rest)
        end
      end
    end
  end
end
