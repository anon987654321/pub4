# frozen_string_literal: true

require "monitor"

module Master
  module Trace
  class EventBus
    include MonitorMixin

    BOOT_TIME         = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
    PATTERN_CACHE_MAX = 512

    def initialize
      super()
      @subscribers   = Hash.new { |h, k| h[k] = [] }
      @pattern_cache = {}
    end

    def subscribe(pattern, &handler)
      synchronize { @subscribers[pattern] << handler }
      -> { synchronize { @subscribers[pattern].delete(handler) } }
    end

    def publish(event, payload = {})
      ts      = elapsed_ms
      payload = payload.merge(event:, ts:)
      handlers = synchronize { matching_handlers(event) }
      Master::Trace::Telemetry.span("event_bus.publish", event:, n_handlers: handlers.size) do
        handlers.each { |h| h.call(payload) rescue nil }
      end
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

    def glob_match?(pattern, event)
      @pattern_cache.shift if @pattern_cache.size >= PATTERN_CACHE_MAX
      re = @pattern_cache[pattern] ||= Regexp.new(
        "\\A" + Regexp.escape(pattern).gsub("\\*\\*", ".*").gsub("\\*", "[^:]*") + "\\z"
      )
      re.match?(event)
    end
  end
  end
end
