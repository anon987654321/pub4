# frozen_string_literal: true

require_relative "lane_quota"

module Master
  module Io
    # Silences a lane after SILENT_AFTER failures in a row for SILENCE_COOLOFF_S,
    # saying so once; one answer clears it. Per lane so a spent lane cannot shut
    # one that answers; process-wide because every session shares the lanes.
    module LaneSilence
      SILENT_AFTER = 12
      SILENCE_COOLOFF_S = 300
      ANY = "any"

      @mutex = Mutex.new
      @lanes = {}

      # Quota and silence must agree about shared provider boundaries.
      def self.lane_of(model)
        LaneQuota.lane_of(model).then { |lane| lane.empty? ? ANY : lane }
      end

      def self.silent?(lane = ANY)
        sync { (@lanes[lane] || {}).fetch(:silent_until, 0.0) > now }
      end

      # A lane that blew a hard call deadline is silent at once for the cool-off:
      # twelve more calls at the full deadline would cost the run its hour.
      def self.silence(lane, reason: nil)
        sync do
          state = (@lanes[lane] ||= { failures: 0, silent_until: 0.0 })

          state[:reason] = reason.to_s.strip unless reason.to_s.strip.empty?
          state[:failures] = 0
          state[:silent_until] = now + SILENCE_COOLOFF_S
        end
      end

      # True only on the call that trips the lane, so the caller says it once.
      def self.record(answered, lane = ANY, reason: nil)
        sync do
          next clear(lane) if answered

          state = (@lanes[lane] ||= { failures: 0, silent_until: 0.0 })
          state[:reason] = reason.to_s.strip unless reason.to_s.strip.empty?
          state[:failures] += 1
          next false if state[:failures] < SILENT_AFTER

          state[:silent_until] = now + SILENCE_COOLOFF_S
          state[:failures] = 0
          true
        end
      end

      # A due manual-exclusion canary is the one bounded probe allowed through
      # a previous silence; all ordinary requests still respect both guards.
      def self.refuses?(model)
        return false if LaneQuota.manual_probe?(model)

        silent?(lane_of(model)) || LaneQuota.dead?(model)
      end

      # A lane that is down says why and when it is back; otherwise the silence message.
      def self.refusal(model)
        lane = lane_of(model)
        return message(lane) if silent?(lane)

        LaneQuota.report_for(model) || "#{lane}: dead (quota)"
      end

      def self.message(lane = ANY)
        said = sync { @lanes.dig(lane, :reason) }
        "no #{lane} answer in #{SILENT_AFTER} calls in a row; #{lane} is skipped for " \
          "#{SILENCE_COOLOFF_S / 60} minutes#{say(said)}. /model list says what each lane needs."
      end

      def self.say(reason) = reason ? " (last: #{reason.lines.first.to_s.strip[0, 200]})" : ""

      def self.now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      def self.clear(lane)
        @lanes.delete(lane)
        false
      end

      def self.sync(&) = @mutex.synchronize(&)

      private_class_method :say, :now, :clear, :sync
    end
  end
end
