# frozen_string_literal: true

module MASTER
  # Lane — serial execution queue (OpenCrabs Lane Queue pattern).
  #
  # Enforces one agent turn per session at a time. Eliminates race conditions
  # on session state, file writes, and LLM context window management.
  # Concurrency is a system-level decision, not a per-call afterthought.
  #
  # Threads permitted outside the lane: web server, heartbeat, TTS playback.
  #
  # Usage:
  #   Lane.run(:analyze)                { expensive_operation }
  #   Lane.run(:refactor, timeout: 120) { llm_rewrite(file) }
  module Lane
    LANE_TIMEOUT   = 300 # seconds — max per operation
    QUEUED_TIMEOUT =  60 # seconds — max wait for lane to clear

    @mutex   = Mutex.new
    @cv      = ConditionVariable.new
    @running = false
    @queue   = []

    class << self
      # Run block exclusively. Returns block value, or Result.err on timeout/error.
      # @param name [Symbol] operation label for dmesg logging
      # @param timeout [Integer] max seconds
      def run(name, timeout: LANE_TIMEOUT, &block)
        acquire!(name)
        Timeout.timeout(timeout) { block.call }
      rescue Timeout::Error
        log_lane("timeout name=#{name} after=#{timeout}s")
        Result.err("Lane #{name} timed out after #{timeout}s")
      rescue StandardError => e
        log_lane("error name=#{name} err=#{e.message}")
        Result.err("Lane #{name} failed: #{e.message}")
      ensure
        release!(name)
      end

      def busy?  = @mutex.synchronize { @running }
      def depth  = @mutex.synchronize { @queue.size }

      private

      def acquire!(name)
        deadline = Time.now + QUEUED_TIMEOUT
        @mutex.synchronize do
          @queue << name
          loop do
            break unless @running
            raise Timeout::Error if Time.now >= deadline

            @cv.wait(@mutex, 0.5)
          end
          @queue.delete(name)
          @running = true
          log_lane("acquired name=#{name} queue=#{@queue.size}")
        end
      end

      def release!(name)
        @mutex.synchronize do
          @running = false
          log_lane("released name=#{name} depth=#{@queue.size}")
          @cv.broadcast
        end
      end

      def log_lane(msg)
        defined?(Logging) ? Logging.dmesg_log("lane0", message: msg) : warn("lane0: #{msg}")
      end
    end
  end
end
