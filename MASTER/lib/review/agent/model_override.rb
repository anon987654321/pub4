# frozen_string_literal: true

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
        def model = @pinned_model || routed_models.first

        def model=(val)
          chosen = resolve_model_name(val.to_s)
          @config["model"] = chosen
          @pinned_model = chosen
        end

        def with_model(override, &blk)
          @model_mutex ||= Mutex.new
          @model_mutex.synchronize do
            saved = [@pinned_model, @config["model"]]
            self.model = override
            blk.call
          ensure
            @pinned_model, @config["model"] = saved
          end
        end

        # The session's model at boot. /model saves its choice to config, so an
        # online boot puts that choice first again; a config still holding the
        # default chose nothing and leaves the routed chain in charge. A saved
        # model the pool cannot reach any more — a key removed, a model deleted —
        # is passed over with one line, as OpenCode passes over a stale recent
        # model, rather than pinned to fail every call of the session.
        def pin_boot_model!
          start_on_local_tier_when_offline!
          saved = @config["model"].to_s
          return if @pinned_model || saved.empty? || saved == Ground::Config::DEFAULTS["model"]

          reason = @model_router.unreachable_reason(saved, wait: true) if @model_router.respond_to?(:unreachable_reason)
          return @pinned_model = saved unless reason

          Trace::Dmesg.once("model0", "#{saved} passed over, #{reason}")
        end

        # Offline, every remote lane costs a resolver timeout before
        # FallbackChain reaches the local tier, so a session that starts with
        # no network starts there. Not saved to config: the network coming
        # back gives the routed chain back on the next boot.
        def start_on_local_tier_when_offline!
          return if @pinned_model || Ground::BootReceipt.network?

          local = @model_router.respond_to?(:local_models) ? Array(@model_router.local_models).first : nil
          @pinned_model = local if local
        end

        # A pinned model that just failed is parked in the skip cache, and the
        # scan's model rules ask here one after another; they route around it
        # until it comes back instead of each failing on it in turn.
        def model_for(operation:)
          pinned = @pinned_model unless @pinned_model && Io::ModelSkipCache.skipped?(@pinned_model)
          pinned || @model_router&.constrained_for(operation:) || model
        end

        # The full fallback chain (cheap-first/strong-first as configured),
        # not just the first candidate -- callers checking circuit-breaker
        # health need every candidate this dispatch could actually fall
        # back to, not only the one at the front of the chain.
        def candidate_models(message = nil, task_type: nil) = routed_models(message, task_type:)

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
