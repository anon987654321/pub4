# frozen_string_literal: true

require "time"

module Master
  module Ground
    # OpenClaw OPENCLAW_FALLBACK_SKIP_TTL_MS parity — skip models that recently failed
    # auth/rate/quota so failover chains do not hammer the same dead endpoint.
    module ModelSkipCache
      SKIP_CATEGORIES = %i[
        rate_limit quota_exceeded no_api_key timeout auth_error
        provider_error llm_call_failure
      ].freeze

      @mutex = Mutex.new
      @skips = {}

      module_function

      def skip_ttl_ms
        env = ENV["MASTER_FALLBACK_SKIP_TTL_MS"].to_s
        return env.to_i if env.match?(/\A\d+\z/) && env.to_i.positive?

        val = models_failover_cfg["skip_ttl_ms"].to_i
        val.positive? ? val : 600_000
      end

      def skip!(model, reason:, category: nil)
        ttl = skip_ttl_ms
        return if ttl <= 0 || model.to_s.empty?

        cat = category&.to_sym
        return if cat && !SKIP_CATEGORIES.include?(cat)

        until_ms = (Process.clock_gettime(Process::CLOCK_REALTIME) * 1000).round + ttl
        @mutex.synchronize do
          @skips[model.to_s] = { until_ms:, reason: reason.to_s, category: cat&.to_s }
        end
      end

      def skipped?(model)
        entry = @mutex.synchronize { @skips[model.to_s] }
        return false unless entry

        now_ms = (Process.clock_gettime(Process::CLOCK_REALTIME) * 1000).round
        if now_ms >= entry[:until_ms]
          @mutex.synchronize { @skips.delete(model.to_s) }
          return false
        end
        true
      end

      def skip_reason(model)
        @mutex.synchronize { @skips[model.to_s]&.dig(:reason) }
      end

      # Why the model is parked, as the symbol the Result carried. A caller
      # that must decide whether to route around this model or merely retry it
      # needs the kind, not the prose: a spend limit or a refused key wants a
      # different lane, a timeout wants the same one again.
      def skip_category(model)
        @mutex.synchronize { @skips[model.to_s]&.dig(:category)&.to_sym }
      end

      def filter(models)
        Array(models).reject { |model| skipped?(model) }
      end

      def clear!
        @mutex.synchronize { @skips.clear }
      end

      def models_failover_cfg
        path = File.join(Master::ROOT, "data", "models.yml")
        Master.load_yaml(path).fetch("failover", {})
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "ModelSkipCache.models_failover_cfg")
        {}
      end
      private_class_method :models_failover_cfg
    end
  end
end
