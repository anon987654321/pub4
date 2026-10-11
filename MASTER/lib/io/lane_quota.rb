# frozen_string_literal: true

require "yaml"
require_relative "atomic_write"
require_relative "lane_reply"

module Master
  module Io
    # A lane whose provider says its quota is spent is dead until the provider
    # says it is back. agy answers "Individual quota reached ... Resets in
    # 165h22m49s" and the dispatcher used to learn that again every five minutes,
    # twelve calls at a time, because LaneSilence counts failures and cannot read
    # a reply. One such reply is enough here: the lane is dead until now plus the
    # stated wait (an hour when none is stated, eight days at most) and the
    # deadline is written under .master so a new process starts knowing.
    #
    # `dead?` is the one reader. It folds in the hand-kept `dead:` list of
    # data/model_roles.yml, so role resolution, the dispatcher door, failover and
    # the pinned council critic all ask the same question.
    module LaneQuota
      extend self
      include ::Master::Io::AtomicWrite

      UNKNOWN_WAIT_S = LaneReply::UNKNOWN_WAIT_S
      MAX_WAIT_S = LaneReply::MAX_WAIT_S
      PROBE_EVERY_S = 600
      UNKNOWN_PREFIX = "unknown:"
      DATA = File.expand_path("../../data/model_roles.yml", __dir__)

      @mutex = Mutex.new
      @clock = -> { Time.now.to_f }
      @path = nil

      attr_writer :clock, :path

      def path = @path || ENV["MASTER_LANE_QUOTA_PATH"] || File.expand_path("../../.master/lane_quota.yml", __dir__)

      def lane_of(model) = model.to_s.split(":", 2).first.to_s

      # Seconds a reply says to wait; nil when it names none.
      def wait_in(reply) = LaneReply.stated_wait(reply.to_s, @clock.call)

      def spent?(reply) = !LaneReply.read(reply, now: @clock.call).nil?

      # Marks the model's lane dead when the reply says its quota is spent, its
      # session limit hit, its daemon unreachable or its login expired.
      # Returns the deadline (epoch seconds) or nil when the reply says no such thing.
      # A wait the reply did not state is marked, so `due_probes` can re-test it.
      def note(model, reply)
        verdict = LaneReply.read(reply, now: @clock.call)
        return unless verdict

        lane = lane_of(model)
        deadline = @clock.call + verdict.wait
        @mutex.synchronize do
          rows = raw.merge(lane => deadline)
          rows.delete(UNKNOWN_PREFIX + lane)
          rows[UNKNOWN_PREFIX + lane] = deadline if verdict.unknown
          write(rows)
        end
        deadline
      end

      # Lanes marked dead by a guessed wait that have been dead long enough to try again.
      def due_probes(every: PROBE_EVERY_S)
        @mutex.synchronize { raw }.filter_map do |key, deadline|
          next unless key.start_with?(UNKNOWN_PREFIX)

          key.delete_prefix(UNKNOWN_PREFIX) if @clock.call - (deadline - UNKNOWN_WAIT_S) >= every
        end
      end

      # Clears a lane so the next call asks it; a lane still spent is marked again by that call.
      def revive(lane)
        @mutex.synchronize { write(raw.reject { |key, _| key == lane || key == UNKNOWN_PREFIX + lane }) }
      end

      def dead?(model, manual: manual_dead) = until_for(model, manual:) != nil

      # Epoch deadline, :manual for the hand-kept list, or nil when the lane is live.
      def until_for(model, manual: manual_dead)
        return :manual if manual.any? { |entry| model.to_s.start_with?(entry) }

        @mutex.synchronize { table[lane_of(model)] }
      end

      # lane => deadline, expired rows dropped; the file is the shared truth.
      def table = raw.reject { |key, _| key.start_with?(UNKNOWN_PREFIX) }

      def raw
        rows = YAML.safe_load_file(path) || {}
        rows.select { |_lane, deadline| deadline.is_a?(Numeric) && deadline > @clock.call }
      rescue Errno::ENOENT
        {}
      rescue StandardError => e
        swallow(e, "Io::LaneQuota.table")
        {}
      end

      def dead_lanes = (manual_dead.to_h { |lane| [lane, :manual] }).merge(@mutex.synchronize { table })

      # "agy: quota spent, back in 140h44m (2026-10-17 04:12)" lines for status output.
      def report
        dead_lanes.map do |lane, deadline|
          next "#{lane}: dead by hand (data/model_roles.yml dead:)" if deadline == :manual

          left = (deadline - @clock.call).to_i
          back = Time.at(deadline).strftime("%Y-%m-%d %H:%M")
          "#{lane}: quota spent, back in #{left / 3600}h#{left % 3600 / 60}m (#{back})"
        end
      end

      # Entries are plain strings or "agy:" which YAML reads as a one-key map.
      def manual_dead(source = DATA)
        list = source.is_a?(Hash) ? source["dead"] : YAML.safe_load_file(source)&.fetch("dead", nil)
        Array(list).flat_map { |e| e.is_a?(Hash) ? e.keys : [e] }.map { |e| e.to_s.strip.chomp(":") }.reject(&:empty?)
      rescue StandardError => e
        swallow(e, "Io::LaneQuota.manual_dead")
        []
      end

      private

      # Standalone: the operator reads this without booting the runtime.
      def swallow(error, context)
        defined?(Master::Ground::Swallow) ? Master::Ground::Swallow.log(error, context:) : warn("#{context}: #{error.message}")
      end

      def write(rows) = write_atomic(path, rows.to_yaml)
    end
  end
end
