# frozen_string_literal: true

require_relative "../../execution/contract"
module Master
  module Review
    class Agent
      # Read/override the active model (distinct from ModelSelector's routing
      # logic) -- grouped apart to keep Agent itself under the NO_GOD_CLASS
      # public-method ceiling. Same include pattern as PromptFilter/
      # ModelSelector/PromptBuilder/FallbackChain already on this class.
      module ModelOverride
        # What the operator may type for "the local tier".
        LOCAL_TIER_NAMES = %w[local ollama].freeze

        # A model the operator chose leads every chain until another is chosen.
        # config["model"] alone sits at the tail of the routed chain, where no
        # turn reaches it while an earlier lane answers.
        def model
          live = @runtime_model.to_s.empty? ? nil : @runtime_model
          return live if live && @model_router&.unreachable_reason(live, wait: false).nil?

          @runtime_model = nil if live
          routed_models.first
        rescue StandardError => e
          @bus&.publish("llm:model_state_error", error_class: e.class.name, **Master::Execution::Contract.diagnostic_fields(e.message))
          routed_models.first
        end

        def model=(val)
          chosen = resolve_model_name(val.to_s)
          @config["model"] = chosen
          @pinned_model = chosen
          @runtime_model = nil
        end

        def with_model(override, &blk)
          @model_mutex ||= Mutex.new
          @model_mutex.synchronize do
            saved = [@pinned_model, @config["model"], @runtime_model]
            self.model = override
            blk.call
          ensure
            @pinned_model, @config["model"], @runtime_model = saved
          end
        end

        # /model may save a provider that later disappears. Keep an explicit
        # choice while it remains reachable; otherwise leave selection to the
        # live router instead of pinning a dead lane.
        def pinned_model_reachable_for(model_id)
          return true unless @model_router.respond_to?(:unreachable_reason)
          @model_router.unreachable_reason(model_id, wait: false).nil?
        rescue StandardError => e
          @bus&.publish("llm:model_reachability_error", model: model_id, error_class: e.class.name, **Master::Execution::Contract.diagnostic_fields(e.message))
          false
        end

        # The saved model is a preference, not a pin: it leads the routed chain
        # while it is live and no worse a class than the best live lane, and an
        # operation that asks the router for a lane (model_for) is chosen by
        # availability alone. Only /model (model=) and MASTER_MODEL pin. A saved
        # cloud model never crosses the local-only boundary. The reachability
        # probe runs once per agent, whatever its answer.
        def pin_boot_model_once!
          return if @boot_pin_checked
          return if local_only?

          @boot_pin_checked = true
          pin_boot_model!
        end

        def pin_boot_model!
          saved = @config["model"].to_s
          return if @pinned_model || saved.empty? || saved == Ground::Config::DEFAULTS["model"]

          reason = @model_router.unreachable_reason(saved, wait: true) if @model_router.respond_to?(:unreachable_reason)
          return @preferred_model = saved unless reason

          Trace::Dmesg.once("model0", "#{saved} unavailable; live pool selected")
        end

        # A pinned model that just failed is parked in the skip cache, and the
        # scan's model rules ask here one after another; they route around it
        # until it comes back instead of each failing on it in turn.
        # A successful fallback becomes the live model for subsequent
        # turns when the operator did not explicitly pin one. This changes
        # runtime state, not the persistent preference, and lets the next prompt
        # surface the model that actually answers instead of the dead one.
        def promote_runtime_model(from:, to:)
          return if @pinned_model
          return if from.to_s.empty? || to.to_s.empty? || from.to_s == to.to_s
          @runtime_model = to.to_s
          @bus&.publish("llm:model_switched", from:, to: @runtime_model, reason: "fallback_success")
        rescue StandardError => e
          @bus&.publish("llm:model_switch_error", from:, to:, error_class: e.class.name, **Master::Execution::Contract.diagnostic_fields(e.message))
        end

        def model_for(operation:)
          Fiber[:master_operation] = operation
          forced = ENV["MASTER_MODEL"].to_s.strip
          if !local_only? && !forced.empty? &&
             (!@model_router.respond_to?(:unreachable_reason) ||
              @model_router.unreachable_reason(forced, wait: false).nil?)
            return forced
          end

          pin_boot_model_once!
          pinned = @pinned_model if @pinned_model && Io::LaneState.usable?(@pinned_model) &&
                                   pinned_model_reachable?
          runtime = @runtime_model if @runtime_model && Io::LaneState.usable?(@runtime_model) &&
                                      pinned_model_reachable_for(@runtime_model)
          pinned || runtime || @model_router&.constrained_for(operation:) || model
        end

        # The full fallback chain (cheap-first/strong-first as configured),
        # not just the first candidate -- callers checking circuit-breaker
        # health need every candidate this dispatch could actually fall
        # back to, not only the one at the front of the chain.
        # MASTER_MODEL leads every call at LLMDispatcher#answering_model and is
        # the first candidate here, with the routed chain behind it: a pin is the
        # first choice, so a pinned lane that is dead or errors fails over to the
        # next live lane instead of ending the call.
        def candidate_models(message = nil, task_type: nil)
          forced = ENV["MASTER_MODEL"].to_s.strip
          routed = routed_models(message, task_type:)
          forced.empty? ? routed : ([forced] + routed).uniq
        end

        private

        def resolve_model_name(name)
          return name unless LOCAL_TIER_NAMES.include?(name.downcase)

          local = @model_router.respond_to?(:local_models) ? Array(@model_router.local_models).first : nil
          local || raise(ArgumentError, "no local model pulled; run ollama pull, then /model local")
        end
      end
    end
  end
end
