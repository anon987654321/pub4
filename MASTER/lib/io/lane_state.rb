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
    # router adds its measured health on top, per instance. Nothing outside
    # lib/io/lane_*.rb reads a store's refusal itself (test_lane_state holds it).
    module LaneState

      Verdict = Data.define(:model, :source, :reason) do
        def usable? = source.nil?
      end

      # Every store, in the order a refusal is named.
      SOURCES = %i[dead silent parked spent daily_quota].freeze

      # The lane itself is down — dead by its quota record, the hand list or this
      # run, or silent for its cool-off — not a model that failed one call. What
      # an offline line describes, and what the dispatcher door refuses: a door
      # that refused parked models would hand callers a :no_api_key failure they
      # re-park for the full ten minutes, outliving a thirty-second park.
      DOWN = %i[dead silent].freeze

      module_function

      # `sources:` narrows the question for a site that must keep something the
      # other stores refuse; each such site says why beside the call.
      def verdict(model, sources: SOURCES)
        id = model.to_s
        source, reason = refusal(id, sources:)
        Verdict.new(model: id, source:, reason:)
      end

      def usable?(model, sources: SOURCES) = verdict(model, sources:).usable?

      HEALTH_OF = { dead: "failed", silent: "degraded", parked: "degraded", spent: "unavailable",
                    daily_quota: "unavailable" }.freeze

      # In Operator::HEALTH words. A usable lane is ready only when its latest call
      # succeeded; one never asked is configured.
      def health(model, succeeded: false)
        state = verdict(model)
        return "#{HEALTH_OF.fetch(state.source)}: #{state.reason}" unless state.usable?

        succeeded ? "ready" : "configured: not asked yet"
      end

      def filter(models, sources: SOURCES) = Array(models).select { |model| usable?(model, sources:) }

      # [source, reason] for the first store that refuses the model, or nil.
      def refusal(id, sources: SOURCES)
        sources.each do |source|
          reason = public_send(:"#{source}_reason", id)
          return [source, reason] if reason
        end
        nil
      end

      # A due manual-exclusion canary is the one call let through a down lane.
      def dead_reason(id)
        return if LaneQuota.manual_probe?(id) || !LaneQuota.dead?(id)

        lane = LaneQuota.lane_of(id)
        dropped = LaneQuota.run_drops[lane]
        LaneQuota.report_for(id) || (dropped ? "#{lane}: dropped for this run (#{dropped})" : "#{lane}: dead (quota)")
      end

      def silent_reason(id)
        lane = LaneSilence.lane_of(id)
        LaneSilence.message(lane) if !LaneQuota.manual_probe?(id) && LaneSilence.silent?(lane)
      end

      def parked_reason(id) = ("parked: #{ModelSkipCache.skip_reason(id)}" if ModelSkipCache.skipped?(id))

      def spent_reason(id) = ("paid tier spent (QuotaCheck)" if QuotaCheck.blocked?(id))

      def daily_quota_reason(id) = ("free daily quota used (ModelQuota)" if ModelQuota.over_quota?(id))

      # The lane bookkeeping other layers print or key on, read here so the
      # stores have one reader outside lib/io.
      def lane_of(model) = LaneQuota.lane_of(model)

      def report = LaneQuota.report

      def run_drops = LaneQuota.run_drops

      def manual_dead = LaneQuota.manual_dead

      def due_probes = LaneQuota.due_probes
    end
  end
end
