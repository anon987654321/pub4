# frozen_string_literal: true

module MASTER
  # Heartbeat -- background timer that checks for pending work
  # Inspired by OpenClaw's heartbeat-runner: fires periodically,
  # evaluates what needs doing, acts without user prompting
  module Heartbeat
    extend self

    DEFAULT_INTERVAL = 60 # seconds
    MAX_INTERVAL = 3600

    @running = false
    @thread = nil
    @interval = DEFAULT_INTERVAL
    @checks = []
    @checks_mutex = Mutex.new

    class << self
      attr_reader :running, :interval

      def start(interval: DEFAULT_INTERVAL)
        return if @running

        @interval = interval.clamp(5, MAX_INTERVAL)
        @running = true
        Logging.dmesg_log("heartbeat", message: "ENTER start interval=#{@interval}s")

        @thread = Thread.new { run_loop }
        @thread.abort_on_exception = false
      end

      def stop
        @running = false
        @thread&.join(5)
        @thread = nil
        Logging.dmesg_log("heartbeat", message: "EXIT stop")
      end

      # Register a check -- callable that returns work items or nil
      def register(name, &block)
        @checks_mutex.synchronize do
          @checks << { name: name, callable: block, last_run: nil, failures: 0 }
        end
      end

      def clear
        @checks_mutex.synchronize do
          @checks = []
        end
      end

      def status
        @checks_mutex.synchronize do
          {
            running: @running,
            interval: @interval,
            checks: @checks.map { |c| { name: c[:name], last_run: c[:last_run], failures: c[:failures] } }
          }
        end
      end

      private

      def run_loop
        while @running
          @checks_mutex.synchronize do
            @checks.each { |check| run_check(check) }
          end
          sleep(@interval)
        end
      rescue StandardError => e
        Logging.dmesg_log("heartbeat", message: "loop error: #{e.message}")
        @running = false
      end

      def run_check(check)
        check[:last_run] = Time.now
        result = check[:callable].call
        check[:failures] = 0 if result
        result
      rescue StandardError => e
        check[:failures] += 1
        backoff = [30 * (2**check[:failures]), MAX_INTERVAL].min
        Logging.dmesg_log("heartbeat", message: "#{check[:name]} failed (#{check[:failures]}x), backoff #{backoff}s: #{e.message}")
        sleep(backoff) if check[:failures] > 2
      end
    end
  end
end
