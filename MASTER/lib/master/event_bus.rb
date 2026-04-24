# frozen_string_literal: true

require "monitor"

module Master
  class EventBus
    include MonitorMixin

    BOOT_TIME = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)

    def initialize(log: nil)
      super()
      @subscribers   = Hash.new { |h, k| h[k] = [] }
      @log           = log
      @pattern_cache = {}
    end

    # Returns a lambda that unsubscribes this handler when called.
    def subscribe(pattern, &handler)
      synchronize { @subscribers[pattern] << handler }
      -> { synchronize { @subscribers[pattern].delete(handler) } }
    end

    def publish(event, payload = {})
      ts      = elapsed_ms
      payload = payload.merge(event:, ts:)
      @log&.push("[#{ts}ms] #{event}: #{payload.except(:event, :ts).inspect}")
      synchronize { matching_handlers(event) }.each { |h| h.call(payload) }
      self
    end

    private

    def elapsed_ms
      Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond) - BOOT_TIME
    end

    def matching_handlers(event)
      @subscribers.flat_map { |pattern, handlers|
        handlers if glob_match?(pattern, event)
      }.compact
    end

    # Compiles glob pattern to regex once; ** crosses segments, * does not.
    def glob_match?(pattern, event)
      re = @pattern_cache[pattern] ||= Regexp.new(
        "\\A" + Regexp.escape(pattern).gsub('\\*\\*', '.*').gsub('\\*', '[^:]*') + "\\z"
      )
      re.match?(event)
    end
  end
end
