# frozen_string_literal: true

require "time"
require_relative "lane_reply"

module Master
  module Io
    # Skip models that recently failed auth/rate/quota so failover chains do not
    # hammer the same dead endpoint. A skip is per model and expires; a spent
    # paid tier is QuotaCheck (test/test_quota_check.rb), and a free model's daily
    # count is ModelQuota.
    module ModelSkipCache
      SKIP_CATEGORIES = %i[
        rate_limit quota_exceeded no_api_key timeout auth_error
        provider_error llm_call_failure model_missing
      ].freeze

      # A failure that says nothing about the next call parks a model briefly. One
      # "Upstream error from Nvidia: Service temporarily overloaded" parked the only
      # lane ai.brgen.no could reach for the full ten minutes, and every turn in
      # that window walked a chain of lanes with no credit and failed after 268s
      # (measured 2026-09-15). A spent key, a quota or a rate limit keeps the long park.
      TRANSIENT_CATEGORIES = %i[timeout provider_error llm_call_failure].freeze

      # A park the provider did not time escalates with the model's own failures
      # in the last day: the first is transient_skip_ttl_ms, then a minute, then
      # five. A success clears the count (OpenClaw's cooldown ladder).
      ESCALATION_MS = [60_000, 300_000].freeze
      STRIKE_WINDOW_MS = 86_400_000

      # In the last two minutes of a longer park, one call is let through every
      # thirty seconds, so a lane that recovered early is seen to have.
      PROBE_LEAD_MS = 120_000
      PROBE_EVERY_MS = 30_000
      PROBE_OPEN_MS = 5_000

      @mutex = Mutex.new
      @skips = {}
      @strikes = {}
      @clock = nil

      module_function

      def clock=(callable)
        @clock = callable
      end

      def now_ms = (@clock ? @clock.call : Process.clock_gettime(Process::CLOCK_REALTIME) * 1000).round

      def skip_ttl_ms
        env = ENV["MASTER_FALLBACK_SKIP_TTL_MS"].to_s
        return env.to_i if env.match?(/\A\d+\z/) && env.to_i.positive?

        val = models_failover_cfg["skip_ttl_ms"].to_i
        val.positive? ? val : 600_000
      end

      def transient_skip_ttl_ms
        val = models_failover_cfg["transient_skip_ttl_ms"].to_i
        val = val.positive? ? val : 30_000
        [val, skip_ttl_ms].min
      end

      # A later deadline extends a park and an earlier one never shortens it, so
      # a 30s blip after a stated six-hour reset does not bring the lane back early.
      def skip!(model, reason:, category: nil)
        cat = category&.to_sym
        return if cat && !SKIP_CATEGORIES.include?(cat)

        now = now_ms
        ttl = ttl_ms(category: cat, reason: reason.to_s, now_ms: now, strikes: strike!(model, now))
        return if ttl <= 0 || model.to_s.empty?

        @mutex.synchronize do
          held = @skips[model.to_s]
          until_ms = [now + ttl, held && held[:until_ms] > now ? held[:until_ms] : 0].max
          @skips[model.to_s] = { until_ms:, span_ms: until_ms - now, reason: reason.to_s, category: cat&.to_s }
        end
      end

      # The call came back: the model is neither parked nor counted against.
      def succeeded!(model)
        @mutex.synchronize do
          @skips.delete(model.to_s)
          @strikes.delete(model.to_s)
        end
      end

      def strike!(model, now)
        @mutex.synchronize do
          recent = Array(@strikes[model.to_s]).select { |at| now - at < STRIKE_WINDOW_MS } << now
          @strikes[model.to_s] = recent
          recent.size
        end
      end
      private_class_method :strike!

      # The wait the provider stated wins. A rate limit that states none is
      # parked like a transient failure: the flat ten minutes over-parked a 429
      # that asked for seconds and under-parked a daily quota that asked for hours.
      def ttl_ms(category:, reason:, now_ms:, strikes: 1)
        stated = LaneReply.stated_wait(reason, now_ms / 1000.0) || LaneReply.daily_reset(reason, now_ms / 1000.0)
        return stated.clamp(1, LaneReply::MAX_WAIT_S) * 1000 if stated&.positive?
        return escalated_ms(strikes) if TRANSIENT_CATEGORIES.include?(category) || category == :rate_limit

        skip_ttl_ms
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "ModelSkipCache.ttl_ms")
        skip_ttl_ms
      end
      private_class_method :ttl_ms

      def escalated_ms(strikes)
        ladder = [transient_skip_ttl_ms, *ESCALATION_MS]
        [ladder[[strikes, ladder.size].min - 1], skip_ttl_ms].min
      end
      private_class_method :escalated_ms

      def skipped?(model)
        entry = @mutex.synchronize { @skips[model.to_s] }
        return false unless entry

        now = now_ms
        if now >= entry[:until_ms]
          @mutex.synchronize { @skips.delete(model.to_s) }
          return false
        end
        !probe_open?(entry, now)
      end

      def probe_open?(entry, now)
        return false if entry[:span_ms].to_i <= PROBE_LEAD_MS || entry[:until_ms] - now > PROBE_LEAD_MS

        @mutex.synchronize do
          opened = entry[:probe_ms]
          entry[:probe_ms] = opened = now if opened.nil? || now - opened >= PROBE_EVERY_MS
          now - opened < PROBE_OPEN_MS
        end
      end
      private_class_method :probe_open?

      # Epoch milliseconds the model's park ends, nil when it is not parked.
      def skipped_until_ms(model)
        @mutex.synchronize { @skips[model.to_s]&.dig(:until_ms) }
      end

      def skip_reason(model)
        @mutex.synchronize { @skips[model.to_s]&.dig(:reason) }
      end

      def filter(models)
        Array(models).reject { |model| skipped?(model) }
      end

      def clear!
        @mutex.synchronize do
          @skips.clear
          @strikes.clear
        end
      end

      def models_failover_cfg
        Master.models_config.fetch("failover", {})
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "ModelSkipCache.models_failover_cfg")
        {}
      end
      private_class_method :models_failover_cfg
    end
  end
end
