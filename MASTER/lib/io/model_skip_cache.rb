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

      @mutex = Mutex.new
      @skips = {}

      module_function

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

        now_ms = (Process.clock_gettime(Process::CLOCK_REALTIME) * 1000).round
        ttl = ttl_ms(category: cat, reason: reason.to_s, now_ms:)
        return if ttl <= 0 || model.to_s.empty?

        @mutex.synchronize do
          held = @skips[model.to_s]
          until_ms = [now_ms + ttl, held && held[:until_ms] > now_ms ? held[:until_ms] : 0].max
          @skips[model.to_s] = { until_ms:, reason: reason.to_s, category: cat&.to_s }
        end
      end

      # The wait the provider stated wins. A rate limit that states none is
      # parked like a transient failure: the flat ten minutes over-parked a 429
      # that asked for seconds and under-parked a daily quota that asked for hours.
      def ttl_ms(category:, reason:, now_ms:)
        stated = LaneReply.stated_wait(reason, now_ms / 1000.0) || LaneReply.daily_reset(reason, now_ms / 1000.0)
        return stated.clamp(1, LaneReply::MAX_WAIT_S) * 1000 if stated&.positive?
        return transient_skip_ttl_ms if TRANSIENT_CATEGORIES.include?(category) || category == :rate_limit

        skip_ttl_ms
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "ModelSkipCache.ttl_ms")
        skip_ttl_ms
      end
      private_class_method :ttl_ms

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
        @mutex.synchronize { @skips.clear }
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
