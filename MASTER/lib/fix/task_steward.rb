# frozen_string_literal: true

require "time"

module Master
  module Fix
    # Keeps unfinished conversational missions alive after an individual fold
    # attempt ends. The mission is the durable objective; this steward only wakes
    # the same bounded runner again when the persisted record says it is due.
    class TaskSteward
      POLL_SECONDS = Integer(ENV.fetch("MASTER_TASK_POLL_SECONDS", "15")).clamp(1, 300)

      class << self
        def start!(root:, bus: nil, runner:)
          return if ENV["MASTER_TASK_STEWARD"] == "0"

          @mutex ||= Mutex.new
          @instances ||= {}
          key = File.expand_path(root)
          @mutex.synchronize do
            current = @instances[key]
            return current if current&.alive?

            steward = new(root:, bus:, runner:)
            @instances[key] = steward.start!
          end
        end

        def wake(root: Master::ROOT)
          instance = @instances&.fetch(File.expand_path(root), nil)
          instance&.wake!
        rescue StandardError
          nil
        end
      end

      def initialize(root:, bus:, runner:)
        @root = File.expand_path(root)
        @bus = bus
        @runner = runner
        @mutex = Mutex.new
        @condition = ConditionVariable.new
        @stop = false
        @wake_requested = false
        @thread = nil
      end

      def start!
        return self if alive?

        @stop = false
        @thread = Thread.new { run_forever }
        @thread.abort_on_exception = false
        self
      end

      def stop!
        @mutex.synchronize do
          @stop = true
          @condition.broadcast
        end
        @thread&.join(2)
        @thread&.kill if @thread&.alive?
        @thread = nil
        self
      end

      def alive? = @thread&.alive? || false

      def wake!
        @mutex.synchronize do
          @wake_requested = true
          @condition.broadcast
        end
        self
      end

      def tick!
        record = Mission.current(root: @root)
        return :idle unless eligible?(record)

        goal = record["goal"].to_s
        @bus&.publish("task_steward:run", mission: record["id"], goal:, attempt: record["attempt_count"].to_i + 1)
        result = @runner.call(goal:, mission: record)
        @bus&.publish("task_steward:result", mission: record["id"], ok: result_ok?(result))
        result
      rescue StandardError => e
        defer_failed_mission(e)
        @bus&.publish("task_steward:error", error: "#{e.class}: #{e.message}")
        Master::Result.err("task steward: #{e.message}", category: :infrastructure)
      end

      private

      def run_forever
        loop do
          break if stopped?

          tick!
          wait_for_wake
        rescue StandardError => e
          @bus&.publish("task_steward:loop_error", error: "#{e.class}: #{e.message}")
          wait_for_wake
        end
        @bus&.publish("task_steward:stop")
      end

      def eligible?(record)
        return false unless record
        return false unless record["origin"].to_s == "fold"
        return false unless record["auto_continue"] == true
        return false unless %w[running waiting].include?(record["state"].to_s)

        due?(record)
      end

      def due?(record)
        return true if record["state"].to_s == "running" && lease_expired?(record)
        return false unless record["state"].to_s == "waiting"

        wake = record["next_wake_at"]
        return true if wake.to_s.empty?

        Time.iso8601(wake.to_s) <= Time.now.utc
      rescue ArgumentError
        true
      end

      def lease_expired?(record)
        wake = record["lease_until"]
        return true if wake.to_s.empty?

        Time.iso8601(wake.to_s) <= Time.now.utc
      rescue ArgumentError
        true
      end

      def wait_for_wake
        seconds = wait_seconds
        @mutex.synchronize do
          return if @stop

          @condition.wait(@mutex, seconds) unless @wake_requested
          @wake_requested = false
        end
      end

      def wait_seconds
        record = Mission.current(root: @root)
        return POLL_SECONDS unless record && record["origin"].to_s == "fold" && record["auto_continue"] == true
        return 0 if record["state"].to_s == "waiting" && due?(record)

        if record["state"].to_s == "waiting"
          wake = record["next_wake_at"].to_s
          return POLL_SECONDS if wake.empty?

          [Time.iso8601(wake) - Time.now.utc, POLL_SECONDS].min.clamp(0, POLL_SECONDS)
        else
          POLL_SECONDS
        end
      rescue ArgumentError
        0
      end

      def defer_failed_mission(error)
        record = Mission.current(root: @root)
        return unless record && record["origin"].to_s == "fold" && record["auto_continue"] == true
        return if leased_by_another_process?(record)

        Mission.new(root: @root, bus: @bus).defer!(
          reason: "steward: #{error.class}: #{error.message}",
          seconds: Mission::RETRY_BASE_SECONDS,
        )
      rescue StandardError => e
        @bus&.publish("task_steward:defer_error", error: "#{e.class}: #{e.message}")
      end

      def leased_by_another_process?(record)
        return false unless record["state"].to_s == "running"

        owner = record["lease_owner"].to_s
        return false if owner.empty? || owner == Mission.instance_id

        !lease_expired?(record)
      end

      def result_ok?(result)
        return result.ok? if result.respond_to?(:ok?)

        result.is_a?(Hash) && result[:reason].to_sym == :complete
      rescue StandardError
        false
      end

      def stopped?
        @mutex.synchronize { @stop }
      end
    end
  end
end
