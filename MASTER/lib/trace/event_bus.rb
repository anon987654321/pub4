# frozen_string_literal: true

require "monitor"

module Master
  module Trace
    class EventBus
      include MonitorMixin

      BOOT_TIME         = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
      PATTERN_CACHE_MAX = 512

      def initialize(event_log: nil)
        super()
        @subscribers   = Hash.new { |h, k| h[k] = [] }
        @pattern_cache = {}
        @event_log     = event_log || Master::Trace::EventLog.new
      end

      def subscribe(pattern, &handler)
        synchronize { @subscribers[pattern] << handler }
        -> { synchronize { @subscribers[pattern].delete(handler) } }
      end

      def publish(event, payload = {})
        ts       = elapsed_ms
        enriched = payload.merge(event:, ts:)
        handlers = synchronize { matching_handlers(event) }

        persist_event(event, enriched)

        Master::Trace::Telemetry.span("event_bus.publish", event:, n_handlers: handlers.size) do
          handlers.each { |h| h.call(enriched) rescue nil }
        end

        self
      end

      private

      def persist_event(event, payload)
        @event_log.append(event, payload)
      rescue StandardError => e
        # warn-only: routing through the bus here would recurse
        Master::Ground::Swallow.log(e, context: "event_bus.persist_event", event:)
      end

      def elapsed_ms
        Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond) - BOOT_TIME
      end

      def matching_handlers(event)
        @subscribers.flat_map do |pattern, handlers|
          handlers if glob_match?(pattern, event)
        end.compact
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
