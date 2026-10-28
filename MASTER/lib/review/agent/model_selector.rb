# frozen_string_literal: true

module Master
  module Review
    class Agent
      module ModelSelector
        TASK_TYPE_ALIASES = {
          coding: :code_generation,
          research: :explanation,
          qa: :explanation,
          architecture: :code_generation,
          general: :general,
        }.freeze

        private

        def routed_models(message = nil, task_type: nil)
          chain = routed_chain(message, task_type:)
          pin_boot_model_once!
          return preference_led(chain) unless @pinned_model
          return chain unless Io::LaneState.usable?(@pinned_model)
          return chain unless pinned_model_reachable?

          ([@pinned_model] + chain).uniq
        end

        # The saved preference goes first while it is reachable (the boot probe)
        # and no worse a class than the chain head; a free model never leads a
        # live subscription lane.
        def preference_led(chain)
          return chain unless @preferred_model && Io::LaneSelection.no_worse_class?(@preferred_model, chain.first)

          ([@preferred_model] + chain).uniq
        end

        def pinned_model_reachable?
          return true unless @model_router.respond_to?(:unreachable_reason)
          @model_router.unreachable_reason(@pinned_model, wait: false).nil?
        rescue StandardError => e
          @bus&.publish("llm:pinned_model_unavailable", model: @pinned_model, error: e.message)
          false
        end

        def routed_chain(message, task_type:)
          return [@config.model] unless @model_router
          task = normalize_task_type(task_type || @config.task_type)
          task = @model_router.classify_intent(message) if task == :general && message
          chain = @model_router.fallback_chain(task_type: task)
          bias = @homeostat&.model_tier_bias
          chain = cheap_first(chain) if bias == :cheap
          chain = strong_first(chain) if bias == :strong

          # Cost/quality bias may reorder within the available pool, but never
          # move browser chat or local compute ahead of the declared fallback ladder.
          @model_router.priority_fallback_order(chain)
        rescue StandardError => e
          @bus&.publish("llm:route_error", error: e.message)
          [@config.model]
        end

        def cheap_first(chain)
          cheap = chain.select { |m| @model_router.tier_for_model(m) == "cheap" }
          rest = chain.reject { |m| @model_router.tier_for_model(m) == "cheap" }
          cheap.empty? ? chain : (cheap + rest)
        end

        def strong_first(chain)
          strong = chain.select { |m| @model_router.tier_for_model(m) == "strong" }
          rest = chain.reject { |m| @model_router.tier_for_model(m) == "strong" }
          strong.empty? ? chain : (strong + rest)
        end

        def normalize_task_type(type)
          sym = type.to_s.delete_prefix(":").to_sym
          TASK_TYPE_ALIASES.fetch(sym, sym)
        end
      end
    end
  end
end
