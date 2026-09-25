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

        # /model may save a provider that later disappears. Keep an explicit
        # choice while it remains reachable; otherwise leave selection to the
        # live router instead of pinning a dead lane.
        def pin_boot_model!
          saved = @config["model"].to_s
          return if @pinned_model || saved.empty? || saved == Ground::Config::DEFAULTS["model"]

          reason = @model_router.unreachable_reason(saved, wait: true) if @model_router.respond_to?(:unreachable_reason)
          return @pinned_model = saved unless reason

          Trace::Dmesg.once("model0", "#{saved} unavailable; dynamic routing (#{reason})")
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
        # MASTER_MODEL replaces every lane at LLMDispatcher#forced_model, so it is
        # the only candidate. Reporting the routed chain instead let /fix's
        # circuit check skip every repair because free lanes it would never call
        # were open, while claude-cli:claude-opus-5-5 stood ready.
        def candidate_models(message = nil, task_type: nil)
          forced = ENV["MASTER_MODEL"].to_s.strip
          forced.empty? ? routed_models(message, task_type:) : [forced]
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
