# frozen_string_literal: true

module Master
  module Review
    class Agent
      # Read/override the active model (distinct from ModelSelector's routing
      # logic) -- grouped apart to keep Agent itself under the NO_GOD_CLASS
      # public-method ceiling. Same include pattern as PromptFilter/
      # ModelSelector/PromptBuilder/FallbackChain already on this class.
      module ModelOverride
        def model = routed_models.first
        def model=(val)
          @config["model"] = val
        end

        def with_model(override, &blk)
          @model_mutex ||= Mutex.new
          @model_mutex.synchronize do
            prev = model
            self.model = override
            blk.call
          ensure
            self.model = prev
          end
        end

        def model_for(operation:)
          @model_router&.constrained_for(operation:) || model
        end

        # The full fallback chain (cheap-first/strong-first as configured),
        # not just the first candidate -- callers checking circuit-breaker
        # health need every candidate this dispatch could actually fall
        # back to, not only the one at the front of the chain.
        def candidate_models(message = nil, task_type: nil) = routed_models(message, task_type:)
      end
    end
  end
end
