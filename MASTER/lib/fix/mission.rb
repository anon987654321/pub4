# frozen_string_literal: true

require "json"
require "fileutils"
require "securerandom"
require "socket"
require "time"
require_relative "../io/atomic_write"

module Master
  module Fix
    # Mission is the durable objective. A FixLoop execution is only one attempt
    # to advance it; process death must never erase the work that remains.
    class Mission
      include Master::Io::AtomicWrite

      VERSION = 2
      REL_PATH = ".master/mission.json"
      LOCK_PATH = ".master/mission.lock"
      MAX_GOAL_BYTES = 2_048
      MAX_PLAN_BYTES = 4_096
      LEASE_SECONDS = 300
      LEASE_RENEW_SECONDS = 60
      RETRY_BASE_SECONDS = 60
      RETRY_MAX_SECONDS = 3_600
      STATES = %w[queued running waiting completed failed blocked interrupted].freeze
      RESUMABLE_STATES = %w[running waiting].freeze
      STAGES = %w[discover plan execute verify deliver].freeze

      attr_reader :root, :id

      def self.instance_id
        if @instance_pid != Process.pid
          @instance_pid = Process.pid
          @instance_id = "#{Socket.gethostname}:#{Process.pid}:#{SecureRandom.hex(8)}"
        end
        @instance_id
      end

      def initialize(root: Master::ROOT, bus: nil, checkpoint: nil)
        @root = File.expand_path(root)
        @bus = bus
        @checkpoint = checkpoint
        @id = nil
        @record = nil
      end

      def start!(goal:, scope: @root, model: nil, effort: "medium", plan: nil, origin: "unknown", auto_continue: false)
        with_lock do
          start_unlocked!(goal:, scope:, model:, effort:, plan:, origin:, auto_continue:)
          persist!
        end
        emit("mission:start", @record.slice("id", "goal", "scope", "model", "effort"))
        self
      end

      # Prepare an objective without consuming an execution attempt. The background
      # supervisor uses this to create work that will be claimed only when due.
      def ensure_queued!(goal:, scope: @root, model: nil, effort: "medium", plan: nil)
        with_lock do
          current = load_record
          if current && current["goal"].to_s == goal.to_s && current["scope"].to_s == relative(scope).to_s &&
             %w[running waiting].include?(current["state"].to_s)
            @record = current
            @id = current["id"]
            return self
          end

          return self if current && current["goal"].to_s == goal.to_s && current["scope"].to_s == relative(scope).to_s &&
                          current["state"].to_s == "blocked"

          raise active_mission_conflict(current, goal:, scope:) if active_for_other_target?(current, goal:, scope:)

          start_unlocked!(goal:, scope:, model:, effort:, plan:)
          @record["state"] = "waiting"
          @record["stage"] = "discover"
          @record["attempt_count"] = 0
          @record["next_wake_at"] = now
          @record["lease_owner"] = nil
          @record["lease_until"] = nil
          persist!
        end
        emit("mission:queued", id: @id, goal: @record["goal"], scope: @record["scope"])
        self
      end

      # Reuse the durable objective when it is still alive. A completed mission
      # is deliberately a new objective on the next wake; a blocked mission may
      # be replaced only by an explicit/manual /fix request.
      def start_or_resume!(goal:, scope: @root, model: nil, effort: "medium", plan: nil, origin: "unknown", auto_continue: false)
        # resumed is read after with_lock returns; assignment inside the block
        # would be block-local and the emit below would see an unset local.
        resumed = false
        with_lock do
          current = load_record
          if reusable_for?(current, scope, goal)
            @record = current
            @id = current["id"]
            claim_unlocked!
            persist!
            resumed = true
          else
            if manually_supersedable?(current, origin:)
              supersede_waiting_unlocked!(current, goal:, scope:)
            elsif active_for_other_target?(current, goal:, scope:)
              raise active_mission_conflict(current, goal:, scope:)
            end

            start_unlocked!(goal:, scope:, model:, effort:, plan:, origin:, auto_continue:)
            persist!
            resumed = false
          end
        end
        emit(resumed ? "mission:resume" : "mission:start", id: @id, goal: @record["goal"],
             scope: @record["scope"], attempt: @record["attempt_count"])
        self
      end

      def transition!(stage, **payload)
        with_lock do
          load_current_unlocked!
          return self unless @record
          stage = stage.to_s
          raise ArgumentError, "unknown mission stage: #{stage}" unless STAGES.include?(stage)

          @record["stage"] = stage
          payload.each { |key, value| assign_payload(key, value) }
          @record["last_seen_at"] = now
          persist!
        end
        emit("mission:stage", id: @id, stage:, **payload)
        self
      end

      def checkpoint!(files: [])
        return self unless @checkpoint

        checkpoint = @checkpoint.call(id: @id, root: @root, files: Array(files)).transform_keys(&:to_s)
        with_lock do
          load_current_unlocked!
          @record["checkpoint"] = checkpoint
          @record["last_seen_at"] = now
          persist!
        end
        emit("mission:checkpoint", id: @id, checkpoint: checkpoint["id"], files: checkpoint["files"].size)
        self
      end

      def heartbeat!
        with_lock do
          load_current_unlocked!
          return self unless @record

          @record["last_seen_at"] = now
          if @record["state"] == "running" && @record["lease_owner"].to_s == self.class.instance_id
            @record["lease_until"] = (Time.now.utc + LEASE_SECONDS).iso8601
          end
          persist!
        end
        self
      end

      # Wake the current mission immediately. Used by file watchers and other
      # event sources; they request work, the supervisor decides when to execute.
      def wake!(reason: "external_event")
        with_lock do
          load_current_unlocked!
          return self unless @record
          return self unless RESUMABLE_STATES.include?(@record["state"].to_s)

          reason = reason.to_s[0, 240]
          if @record["state"].to_s == "running"
            @record["wake_requested"] = true
            @record["wake_reason"] = reason
          else
            @record["state"] = "waiting"
            @record["next_wake_at"] = now
            @record["wake_reason"] = reason
            @record["lease_owner"] = nil
            @record["lease_until"] = nil
          end
          @record["last_seen_at"] = now
          persist!
        end
        emit("mission:wake", id: @id, reason:)
        self
      end

      # Turn a wake received during an attempt into durable work for
      # the next attempt without treating an external event as a retry failure.
      def requeue_if_requested!
        with_lock do
          load_current_unlocked!
          return false unless @record && @record["wake_requested"]

          reason = @record["wake_reason"].to_s
          @record["state"] = "waiting"
          @record["stage"] = "verify"
          @record["next_wake_at"] = now
          @record["wake_requested"] = false
          @record["lease_owner"] = nil
          @record["lease_until"] = nil
          @record["last_seen_at"] = now
          persist!
        end
        emit("mission:requeued", id: @id, reason:)
        true
      end

      def due?
        return false unless @record

        due_at = @record["next_wake_at"]
        return true if due_at.to_s.empty?

        Time.iso8601(due_at.to_s) <= Time.now.utc
      rescue ArgumentError
        true
      end

      def defer!(reason:, seconds: nil)
        # delay/retries are read after with_lock returns; block locals die with it.
        delay = 0
        retries = 0
        with_lock do
          load_current_unlocked!
          return self unless @record

          retries = @record.fetch("retry_count", 0).to_i + 1
          delay = seconds || backoff_seconds(retries)
          @record["state"] = "waiting"
          @record["stage"] = "verify"
          @record["retry_count"] = retries
          @record["next_wake_at"] = (Time.now.utc + delay).iso8601
          @record["wake_reason"] = reason.to_s[0, 240]
          @record["lease_owner"] = nil
          @record["lease_until"] = nil
          @record["last_seen_at"] = now
          persist!
        end
        emit("mission:deferred", id: @id, reason:, delay_seconds: delay, retry_count: retries)
        self
      end

      def block!(reason:)
        with_lock do
          load_current_unlocked!
          return self unless @record

          @record["state"] = "blocked"
          @record["wake_reason"] = reason.to_s[0, 240]
          @record["next_wake_at"] = nil
          @record["lease_owner"] = nil
          @record["lease_until"] = nil
          @record["last_seen_at"] = now
          persist!
        end
        emit("mission:block", id: @id, reason:)
        self
      end

      def finish!(state: "completed", summary: nil)
        state = state.to_s
        raise ArgumentError, "unknown mission state: #{state}" unless STATES.include?(state)

        with_lock do
          load_current_unlocked!
          return self unless @record

          @record["state"] = state
          @record["stage"] = "deliver"
          @record["summary"] = summary.to_s.byteslice(0, 2_048) if summary
          @record["next_wake_at"] = nil
          @record["lease_owner"] = nil
          @record["lease_until"] = nil
          @record["finished_at"] = now
          @record["last_seen_at"] = now
          persist!
        end
        emit("mission:finish", id: @id, state:, summary: @record["summary"])
        self
      end

      def fail!(error)
        with_lock do
          load_current_unlocked!
          return self unless @record

          @record["state"] = "failed"
          @record["error"] = error.to_s.byteslice(0, 1_200)
          @record["lease_owner"] = nil
          @record["lease_until"] = nil
          @record["last_seen_at"] = now
          persist!
        end
        emit("mission:finish", id: @id, state: "failed", error: @record["error"])
        self
      rescue StandardError => e
        warn("mission0: #{e.class}: #{e.message}")
        self
      end

      def artifact!(path)
        return self if path.to_s.empty?

        with_lock do
          load_current_unlocked!
          return self unless @record

          @record["artifacts"] = (@record.fetch("artifacts", []) + [relative(path)]).uniq.last(32)
          @record["last_seen_at"] = now
          persist!
        end
        emit("mission:artifact", id: @id, path: relative(path))
        self
      end

      def record
        @record&.dup
      end

      def self.current(root: Master::ROOT)
        path = File.join(File.expand_path(root), REL_PATH)
        return unless File.file?(path)

        record = JSON.parse(File.read(path, encoding: "UTF-8"))
        migrate_record(record)
      rescue JSON::ParserError => e
        Master::Ground::Swallow.log(e, context: "mission.current")
        nil
      end

      def self.migrate_record(record, now: Time.now.utc.iso8601)
        version = record["version"].to_i
        return record if version == VERSION
        return migrate_v1(record, now:) if version == 1

        raise "mission version #{record["version"]} is unsupported"
      end

      def self.migrate_v1(record, now:)
        state = record["state"].to_s
        unless %w[running completed failed interrupted].include?(state)
          raise "mission v1 state #{state.inspect} is unsupported"
        end

        {
          "version" => VERSION,
          "id" => record["id"].to_s,
          "state" => state == "running" ? "waiting" : state,
          "stage" => STAGES.include?(record["stage"].to_s) ? record["stage"].to_s : "discover",
          "goal" => record["goal"].to_s.byteslice(0, MAX_GOAL_BYTES).to_s,
          "scope" => record["scope"].to_s,
          "model" => record["model"].to_s,
          "effort" => %w[low medium high].include?(record["effort"].to_s.downcase) ? record["effort"].to_s.downcase : "medium",
          "plan" => record["plan"].to_s.byteslice(0, MAX_PLAN_BYTES),
          "summary" => record["summary"],
          "origin" => record["origin"].to_s.empty? ? "legacy" : record["origin"].to_s,
          "auto_continue" => false,
          "started_at" => record["started_at"] || now,
          "finished_at" => record["finished_at"],
          "checkpoint" => record["checkpoint"],
          "artifacts" => Array(record["artifacts"]).map(&:to_s).uniq.last(32),
          "error" => record["error"],
          "attempt_count" => 1,
          "retry_count" => 0,
          "next_wake_at" => state == "running" ? now : nil,
          "wake_reason" => state == "running" ? "migrated from mission v1" : nil,
          "wake_requested" => false,
          "last_seen_at" => record["last_seen_at"] || record["started_at"] || now,
          "lease_owner" => nil,
          "lease_until" => nil,
        }
      end

      def self.block_current(root: Master::ROOT, reason:)
        mission = new(root:)
        mission.send(:load_current_unlocked!)
        mission.block!(reason:)
        mission
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Mission.block_current")
        mission
      end

      private

      def manually_supersedable?(record, origin:)
        origin.to_s == "manual" && record && record["state"].to_s == "waiting" && record["lease_owner"].to_s.empty?
      end

      def supersede_waiting_unlocked!(record, goal:, scope:)
        @record = record
        @id = record["id"]
        @record["state"] = "interrupted"
        @record["stage"] = "deliver"
        @record["summary"] = "superseded by manual /fix for #{relative(scope)}".byteslice(0, MAX_GOAL_BYTES)
        @record["lease_owner"] = nil
        @record["lease_until"] = nil
        @record["next_wake_at"] = nil
        @record["finished_at"] = now
        @record["last_seen_at"] = now
        persist!
      end

      def reusable_for?(record, scope, goal)
        return false unless record
        return false unless RESUMABLE_STATES.include?(record["state"].to_s)
        return false unless record["goal"].to_s == goal.to_s
        return false unless record["scope"].to_s == relative(scope).to_s

        return true unless record["state"].to_s == "running"
        return true if record["lease_owner"].to_s == self.class.instance_id
        return false unless lease_expired?(record)

        true
      end

      def active_for_other_target?(record, goal:, scope:)
        return false unless record
        return false unless RESUMABLE_STATES.include?(record["state"].to_s)

        return false unless mission_live?(record)
        return false if record["goal"].to_s == goal.to_s && record["scope"].to_s == relative(scope).to_s

        true
      end

      def mission_live?(record)
        return false unless record["state"].to_s == "running"
        return false if lease_expired?(record)

        owner = record["lease_owner"].to_s
        return true if owner.empty?
        return true unless owner.start_with?("#{Socket.gethostname}:")

        pid = owner.split(":", 3)[1].to_i
        return true if record["lease_owner"].to_s == self.class.instance_id
        return false if pid <= 0

        process_alive?(pid)
      end

      def process_alive?(pid)
        Process.kill(0, pid.to_i)
        true
      rescue Errno::ESRCH
        false
      rescue Errno::EPERM
        true
      end

      def active_mission_conflict(record, goal:, scope:)
        "mission already active for #{record["scope"]} (requested #{relative(scope)}; #{record["goal"]} != #{goal})"
      end

      def claim_unlocked!
        if @record["state"] == "running" &&
           @record["lease_owner"].to_s != self.class.instance_id &&
           !lease_expired?(@record)
          raise "mission already leased by pid=#{@record["lease_owner"]}"
        end

        @record["state"] = "running"
        @record["stage"] = "execute"
        @record["attempt_count"] = @record.fetch("attempt_count", 0).to_i + 1
        @record["attempt_started_at"] = now
        @record["last_seen_at"] = now
        @record["next_wake_at"] = nil
        @record["wake_reason"] = nil
        @record["lease_owner"] = self.class.instance_id
        @record["lease_until"] = (Time.now.utc + LEASE_SECONDS).iso8601
      end

      def lease_expired?(record)
        value = record["lease_until"]
        return true if value.to_s.empty?

        Time.iso8601(value.to_s) <= Time.now.utc
      rescue ArgumentError
        true
      end

      def start_unlocked!(goal:, scope:, model:, effort:, plan:, origin: "unknown", auto_continue: false)
        @id = SecureRandom.hex(10)
        @record = {
          "version" => VERSION,
          "id" => @id,
          "state" => "running",
          "stage" => "execute",
          "goal" => goal.to_s.byteslice(0, MAX_GOAL_BYTES).to_s,
          "scope" => relative(scope),
          "model" => model.to_s,
          "effort" => normalize_effort(effort),
          "plan" => plan.to_s.byteslice(0, MAX_PLAN_BYTES),
          "summary" => nil,
          "origin" => origin.to_s,
          "auto_continue" => auto_continue == true,
          "started_at" => now,
          "finished_at" => nil,
          "checkpoint" => nil,
          "artifacts" => [],
          "error" => nil,
          "attempt_count" => 1,
          "retry_count" => 0,
          "next_wake_at" => nil,
          "wake_reason" => nil,
          "wake_requested" => false,
          "last_seen_at" => now,
          "lease_owner" => self.class.instance_id,
          "lease_until" => (Time.now.utc + LEASE_SECONDS).iso8601,
        }
      end

      def load_current_unlocked!
        @record = load_record
        @id = @record && @record["id"]
      end

      def load_record
        path = File.join(@root, REL_PATH)
        return unless File.file?(path)

        raw = JSON.parse(File.read(path, encoding: "UTF-8"))
        migrated = self.class.migrate_record(raw)
        persist_record(path, migrated) if migrated["version"].to_i != raw["version"].to_i
        migrated
      rescue JSON::ParserError => e
        Master::Ground::Swallow.log(e, context: "mission.load")
        raise "mission state is corrupt: #{e.message}"
      end

      def backoff_seconds(retries)
        [RETRY_BASE_SECONDS * (2**[retries - 1, 5].min), RETRY_MAX_SECONDS].min
      end

      def normalize_effort(value)
        text = value.to_s.downcase
        %w[low medium high].include?(text) ? text : "medium"
      end

      def assign_payload(key, value)
        case key.to_sym
        when :plan then @record["plan"] = value.to_s.byteslice(0, MAX_PLAN_BYTES)
        when :artifact
          path = relative(value)
          @record["artifacts"] = (@record.fetch("artifacts", []) + [path]).uniq.last(32) if path
        when :checkpoint then @record["checkpoint"] = value
        when :summary then @record["summary"] = value.to_s.byteslice(0, MAX_PLAN_BYTES)
        end
      end

      def persist!
        path = File.join(@root, REL_PATH)
        persist_record(path, @record)
      end

      def persist_record(path, record)
        FileUtils.mkdir_p(File.dirname(path))
        write_atomic(path, JSON.pretty_generate(record) + "\n", mode: 0o600)
      end

      def with_lock
        lock_path = File.join(@root, LOCK_PATH)
        FileUtils.mkdir_p(File.dirname(lock_path))
        File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |io|
          io.flock(File::LOCK_EX)
          yield
        ensure
          io&.flock(File::LOCK_UN)
        end
      end

      def emit(event, payload = {}, **fields)
        @bus&.publish(event, payload.merge(fields))
      rescue StandardError => e
        warn("mission0: #{e.class}: #{e.message}") if ENV["MASTER_TRACE_STRICT"] == "1"
      end

      def relative(path)
        full = File.expand_path(path.to_s, @root)
        root = File.expand_path(@root)
        return path.to_s unless full == root || full.start_with?(root + File::SEPARATOR)

        full.delete_prefix(root + File::SEPARATOR)
      rescue ArgumentError
        path.to_s
      end

      def now = Time.now.utc.iso8601
    end
  end
end
