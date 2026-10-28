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
    # data/lanes.yml, so LaneSelection, the dispatcher door and failover all ask
    # the same question.
    module LaneQuota
      extend self
      include ::Master::Io::AtomicWrite

      UNKNOWN_WAIT_S = LaneReply::UNKNOWN_WAIT_S
      MAX_WAIT_S = LaneReply::MAX_WAIT_S
      PROBE_EVERY_S = 600
      UNKNOWN_PREFIX = "unknown:"
      REASON_PREFIX = "reason:"
      MANUAL_PROBE_PREFIX = "manual-probe:"
      MANUAL_REVIVED_PREFIX = "manual-revived:"
      MANUAL_PROBE_EVERY_S = 3600
      MANUAL_PROBE_KEY = :master_lane_quota_manual_probe
      REASON_TEXT = {
        "quota" => "quota spent",
        "unreachable" => "unreachable",
        "login" => "login expired",
        "guessed" => "quota spent, wait guessed",
      }.freeze
      DATA = File.expand_path("../../data/lanes.yml", __dir__)

      @mutex = Mutex.new
      @clock = -> { Time.now.to_f }
      @path = nil
      @run_drops = {}

      attr_writer :clock, :path

      def path = @path || ENV["MASTER_LANE_QUOTA_PATH"] || File.expand_path("../../.master/lane_quota.yml", __dir__)

      # One cooldown lane per actual quota boundary. CLI ids use `provider:model`;
      # API ids use `vendor/model`. OpenRouter's :free models share a daily
      # free-pool limit, so their vendor slug is not an independent quota lane.
      def lane_of(model)
        id = model.to_s
        return "ollama" if id.start_with?("ollama:", "ollama/")
        # Each website has separate login, quota and failure state. A shared
        # "web-chat" lane would let one broken site silence every browser fallback.
        return id.split(":", 2).first(2).join(":") if id.start_with?("web-chat:")

        colon = id.index(":")
        slash = id.index("/")
        # Hosted IDs are <gateway>:<vendor>/<model>; the gateway owns the
        # quota, even though the upstream model ID itself contains a slash.
        return id[0...colon].to_s if colon && (!slash || colon < slash)
        return id.split("/", 2).first.to_s if slash

        id.split("-", 2).first.to_s
      end

      # OpenRouter's free daily-pool refusal applies to every :free model.
      # Other 429s can be vendor-specific, so they stay on the model's ordinary lane.
      def quota_lane_of(model, reply)
        text = reply.to_s
        free_pool = model.to_s.end_with?(":free") &&
          text.match?(/free-models-per-day/i)
        free_pool ? "openrouter-free" : lane_of(model)
      end

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

        lane = quota_lane_of(model, reply)
        deadline = @clock.call + verdict.wait
        @mutex.synchronize do
          rows = raw.merge(lane => deadline)
          rows.delete(UNKNOWN_PREFIX + lane)
          rows[REASON_PREFIX + lane] = reason_of(verdict)
          rows[UNKNOWN_PREFIX + lane] = deadline if verdict.unknown
          write(rows)
        end
        deadline
      end

      # Why the lane died: the kind of reply, or a guessed wait for a spent one.
      def reason_of(verdict)
        case verdict.kind
        when :unreachable then "unreachable"
        when :auth then "login"
        else verdict.unknown ? "guessed" : "quota"
        end
      end

      # Lanes marked dead by a guessed wait that have been dead long enough to try again.
      def due_probes(every: PROBE_EVERY_S)
        @mutex.synchronize { raw }.filter_map do |key, deadline|
          next unless key.start_with?(UNKNOWN_PREFIX)

          key.delete_prefix(UNKNOWN_PREFIX) if @clock.call - (deadline - UNKNOWN_WAIT_S) >= every
        end
      end

      # Manual exclusions describe lanes that previously failed, not eternal bans.
      # A canary can recheck one known model per run; failed probes cool down,
      # while a verified answer becomes a durable runtime override of the stale row.
      def due_manual_probes(every: MANUAL_PROBE_EVERY_S, known: nil, limit: 1)
        now = @clock.call
        allowed = known && Array(known).map(&:to_s)
        manual_dead.filter_map do |lane|
          next if allowed && !allowed.include?(lane)

          due = @mutex.synchronize do
            rows = raw
            active = rows.any? do |key, deadline|
              next false if key.start_with?(UNKNOWN_PREFIX, REASON_PREFIX, MANUAL_PROBE_PREFIX, MANUAL_REVIVED_PREFIX)
              next false unless deadline.is_a?(Numeric) && deadline > now

              lane.start_with?(key) || key.start_with?(lane)
            end
            next false if active

            key = MANUAL_PROBE_PREFIX + lane
            last = rows[key]
            next false if last.is_a?(Numeric) && now - last < every

            write(rows.merge(key => now))
            true
          end
          lane if due
        end.first([limit.to_i, 1].max)
      end

      # Bypass one configured exclusion only for the current synchronous canary.
      def manual_probe?(model)
        lane = Thread.current[MANUAL_PROBE_KEY].to_s
        !lane.empty? && model.to_s.start_with?(lane)
      end

      def with_manual_probe(lane)
        previous = Thread.current[MANUAL_PROBE_KEY]
        Thread.current[MANUAL_PROBE_KEY] = lane.to_s
        yield
      ensure
        Thread.current[MANUAL_PROBE_KEY] = previous
      end

      # Evidence that a manual exclusion has recovered. The source data remains
      # operator-owned; its effective view drops the prefix after a successful probe.
      def revive_manual(lane)
        @mutex.synchronize do
          write(raw.merge(MANUAL_REVIVED_PREFIX + lane.to_s => true))
        end
      end

      # Clears a lane so the next call asks it; a lane still spent is marked again by that call.
      def revive(lane)
        @mutex.synchronize { write(raw.reject { |key, _| [lane, UNKNOWN_PREFIX + lane, REASON_PREFIX + lane].include?(key) }) }
      end

      # Seconds until the lane of `model` is asked again, or nil when no clock
      # revives it (a hand-kept dead entry, or a lane that is live).
      def revival_in(model)
        deadline = until_for(model)
        deadline.is_a?(Numeric) ? [deadline - @clock.call, 1].max : nil
      end

      def dead?(model, manual: manual_dead) = until_for(model, manual:) != nil

      # A lane this run gave up on (slow or dead at the probe, or failing file after file).
      # Memory only: the next run asks again, and nothing here claims the provider's quota is spent.
      def drop_for_run!(lane, reason)
        @mutex.synchronize { @run_drops[lane.to_s] = reason.to_s }
      end

      def run_drops = @mutex.synchronize { @run_drops.dup }

      def clear_run_drops! = @mutex.synchronize { @run_drops.clear }

      # Epoch deadline, :manual for the hand-kept list, :run for a lane dropped for this run, or nil when the lane is live.
      def until_for(model, manual: manual_dead)
        lane = lane_of(model)
        excluded = manual.find { |entry| model.to_s.start_with?(entry) }
        return :manual if excluded && Thread.current[MANUAL_PROBE_KEY].to_s != excluded
        return :run if @mutex.synchronize { @run_drops.key?(lane) }

        deadlines = @mutex.synchronize { table }
        local = deadlines[lane]
        shared_free = deadlines["openrouter-free"] if model.to_s.end_with?(":free")
        [local, shared_free].compact.max
      end

      # lane => deadline, expired rows dropped; the file is the shared truth.
      def table = raw.reject do |key, _|
        key.start_with?(UNKNOWN_PREFIX, REASON_PREFIX, MANUAL_PROBE_PREFIX, MANUAL_REVIVED_PREFIX)
      end

      # The most specific live status row for a model. The OpenRouter daily
      # free-pool limit covers every :free model; other failures remain vendor-scoped.
      def report_for(model)
        rows = report
        shared = rows.find { |row| row.start_with?("openrouter-free: ") } if model.to_s.end_with?(":free")
        shared || rows.find { |row| row.start_with?("#{lane_of(model)}: ") } ||
          rows.find { |row| (key = row[/\A\S+(?=: )/]) && model.to_s.start_with?(key) }
      end

      # lane => reason for the lanes the file holds; a row with none reads as quota.
      def reasons
        raw.select { |key, _| key.start_with?(REASON_PREFIX) }.transform_keys { |key| key.delete_prefix(REASON_PREFIX) }
      end

      def raw
        rows = YAML.safe_load_file(path) || {}
        live = rows.select do |key, deadline| !key.start_with?(MANUAL_PROBE_PREFIX, MANUAL_REVIVED_PREFIX) &&
                                                   deadline.is_a?(Numeric) && deadline > @clock.call end
        why = rows.select { |key, reason| key.start_with?(REASON_PREFIX) && reason.is_a?(String) && live.key?(key.delete_prefix(REASON_PREFIX)) }
        metadata = rows.select do |key, value|
          (key.start_with?(MANUAL_PROBE_PREFIX) && value.is_a?(Numeric)) ||
            (key.start_with?(MANUAL_REVIVED_PREFIX) && value == true)
        end
        live.merge(why).merge(metadata)
      rescue Errno::ENOENT
        {}
      rescue StandardError => e
        swallow(e, "Io::LaneQuota.table")
        {}
      end

      def dead_lanes = (manual_dead.to_h { |lane| [lane, :manual] }).merge(@mutex.synchronize { table })

      # "agy: quota spent, back in 140h44m (2026-10-17 04:12)" lines for status output.
      def report
        why = @mutex.synchronize { reasons }
        dead_lanes.map do |lane, deadline|
          next "#{lane}: dead by hand (data/lanes.yml dead:)" if deadline == :manual

          left = (deadline - @clock.call).to_i
          back = Time.at(deadline).strftime("%Y-%m-%d %H:%M")
          "#{lane}: #{REASON_TEXT.fetch(why[lane], REASON_TEXT["quota"])}, back in #{left / 3600}h#{left % 3600 / 60}m (#{back})"
        end
      end

      # Entries are plain strings or "agy:" which YAML reads as a one-key map.
      def manual_dead(source = DATA)
        list = source.is_a?(Hash) ? source["dead"] : YAML.safe_load_file(source)&.fetch("dead", nil)
        entries = Array(list).flat_map { |e| e.is_a?(Hash) ? e.keys : [e] }
                          .map { |e| e.to_s.strip.chomp(":") }.reject(&:empty?)
        return entries unless source == DATA

        revived = raw.filter_map do |key, value|
          key.delete_prefix(MANUAL_REVIVED_PREFIX) if key.start_with?(MANUAL_REVIVED_PREFIX) && value == true
        end
        entries.reject { |entry| revived.include?(entry) }
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
