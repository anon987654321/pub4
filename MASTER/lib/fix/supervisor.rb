# frozen_string_literal: true

require "time"

module Master
  module Fix
    # Durable supervisor: scheduling and recovery live outside FixLoop. A worker
    # attempt may die; the mission remains and becomes eligible for another wake.
    class Supervisor
      DEFAULT_POLL_INTERVAL = 30

      def initialize(root:, target:, fix_loop:, bus: nil, wake_mutex: Mutex.new, wake_condition: ConditionVariable.new)
        @root = root
        @target = target
        @fix_loop = fix_loop
        @bus = bus
        @wake_mutex = wake_mutex
        @wake_condition = wake_condition
        @stop = false
      end

      def run_forever
        loop do
          break if stopped?

          result = run_due
          wait_for_next_wake(result)
        rescue StandardError => e
          @bus&.publish("fix_supervisor:error", error: "#{e.class}: #{e.message}")
          Master::Trace::Dmesg.status("fix0", "supervisor error: #{e.class}: #{e.message}")
          wait_for_next_wake(:error)
        end
        @bus&.publish("fix_supervisor:stop")
      end

      def stop!
        @wake_mutex.synchronize do
          @stop = true
          @wake_condition.broadcast
        end
      end

      def wake!(reason: "external_event")
        @bus&.publish("fix_supervisor:wake", reason:)
        @wake_mutex.synchronize { @wake_condition.broadcast }
      end

      private

      def stopped?
        @wake_mutex.synchronize { @stop }
      end

      def run_due
        record = Mission.current(root: @root)
        return :idle unless due_for_target?(record)

        @bus&.publish("fix_supervisor:run", mission: record["id"], target: record["scope"],
                      attempt: record["attempt_count"].to_i + 1)
        result = @fix_loop.run(@target)
        result
      rescue StandardError => e
        @bus&.publish("fix_supervisor:attempt_failed", error: "#{e.class}: #{e.message}")
        mission = Mission.new(root: @root)
        mission.defer!(reason: "supervisor: #{e.class}: #{e.message}", seconds: 60)
        :error
      end

      def due_for_target?(record)
        return false unless record
        return false unless record["scope"].to_s == relative_target
        return false unless %w[running waiting].include?(record["state"].to_s)
        return false unless due?(record)

        return true unless record["state"].to_s == "running"
        return true if record["lease_owner"].to_s == Process.pid.to_s
        return lease_expired?(record)
      end

      def due?(record)
        wake = record["next_wake_at"]
        return true if wake.to_s.empty?

        Time.iso8601(wake.to_s) <= Time.now.utc
      rescue ArgumentError
        true
      end

      def lease_expired?(record)
        value = record["lease_until"]
        return true if value.to_s.empty?

        Time.iso8601(value.to_s) <= Time.now.utc
      rescue ArgumentError
        true
      end

      def wait_for_next_wake(_result)
        return if stopped?

        seconds = next_wait_seconds
        @wake_mutex.synchronize do
          @wake_condition.wait(@wake_mutex, seconds) unless @stop
        end
      end

      def next_wait_seconds
        record = Mission.current(root: @root)
        return poll_interval unless record && record["scope"].to_s == relative_target

        wake = record["next_wake_at"]
        return poll_interval if wake.to_s.empty?

        delay = Time.iso8601(wake.to_s) - Time.now.utc
        [[delay, 0.0].max, poll_interval].min
      rescue ArgumentError
        0.0
      end

      def poll_interval
        value = Master.load_yaml(Master.limits_path).dig("autoloop", "poll_interval").to_f
        value.positive? ? value : DEFAULT_POLL_INTERVAL
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "fix.supervisor.poll_interval")
        DEFAULT_POLL_INTERVAL
      end

      def relative_target
        full = File.expand_path(@target)
        root = File.expand_path(@root)
        return @target.to_s unless full == root || full.start_with?(root + File::SEPARATOR)

        full.delete_prefix(root + File::SEPARATOR)
      end
    end
  end
end