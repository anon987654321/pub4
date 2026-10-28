# frozen_string_literal: true

require_relative "lane_quota"
require_relative "lane_health"
require_relative "lane_silence"
require_relative "model_skip_cache"
require_relative "model_quota"
require_relative "quota_check"

module Master
  module Io
    # Whether a model may be asked now, and if not, which store said no and why.
    # Six stores answered that, each caller combining its own subset, so the
    # retry walk skipped lanes selection had ordered and the dispatcher sent to
    # lanes the router had dropped. The stores keep their bookkeeping; the
    # router adds its measured health on top, per instance.
    module LaneState

      Verdict = Data.define(:model, :source, :reason) do
        def usable? = source.nil?
      end

      module_function

      def verdict(model)
        id = model.to_s
        source, reason = refusal(id)
        Verdict.new(model: id, source:, reason:)
      end

      def usable?(model) = verdict(model).usable?

      HEALTH_OF = { dead: "failed", parked: "degraded", spent: "unavailable", daily_quota: "unavailable" }.freeze

      # In Operator::HEALTH words. A usable lane is ready only when its latest call
      # succeeded; one never asked is configured.
      def health(model, succeeded: false)
        state = verdict(model)
        return "#{HEALTH_OF.fetch(state.source)}: #{state.reason}" unless state.usable?

        succeeded ? "ready" : "configured: not asked yet"
      end

      def filter(models) = Array(models).select { |model| usable?(model) }

      # [source, reason] for the first store that refuses the model, or nil.
      def refusal(id)
        return [:dead, dead_reason(id)] if LaneHealth.dead?(id)
        return [:parked, "parked: #{ModelSkipCache.skip_reason(id)}"] if ModelSkipCache.skipped?(id)
        return [:spent, "paid tier spent (QuotaCheck)"] if QuotaCheck.blocked?(id)
        return [:daily_quota, "free daily quota used (ModelQuota)"] if ModelQuota.over_quota?(id)

        nil
      end

      def dead_reason(id) = LaneSilence.refusal(id)
    end
  end
end
