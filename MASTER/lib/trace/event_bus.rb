# frozen_string_literal: true

require "monitor"

module Master
  module Trace
    class EventBus
      include MonitorMixin

      BOOT_TIME = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
      PATTERN_CACHE_MAX = 512

      def initialize(event_log: nil, evidence_log: nil)
        super()
        @subscribers = Hash.new { |h, k| h[k] = [] }
        @pattern_cache = {}
        @event_log = event_log || Master::Trace::EventLog.new
        @evidence_log = evidence_log
      end

      def subscribe(pattern, &handler)
        synchronize { @subscribers[pattern] << handler }
        -> { synchronize { @subscribers[pattern].delete(handler) } }
      end

      def publish(event, payload = {})
        ts = elapsed_ms
        # One process-wide bus. ChatService (and anything else that writes a
        # visitor's SSE from a handler) must be able to ignore another
        # conversation's events — without this stamp, subscribe("**") and even
        # named tool:before handlers dump visitor B's turn into visitor A's stream.
        enriched = payload.merge(event:, ts:)
        conversation = Fiber[:master_conversation]
        enriched[:conversation] = conversation if conversation
        handlers = synchronize { matching_handlers(event) }

        persist_event(event, enriched)

        Master::Trace::Telemetry.span("event_bus.publish", event:, n_handlers: handlers.size) do
          handlers.each do |h|
            h.call(enriched)
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "event_bus.handler", event:)
          end
        end

        self
      end

      private

      def persist_event(event, payload)
        safe_payload = Master::Ground::Redactor.payload(payload)
        @event_log.append(event, safe_payload)
        @evidence_log&.append(event, safe_payload) if @evidence_log&.operational?(event)
      rescue StandardError => e
        # warn-only: routing through the bus here recurses
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
          "\\A" + Regexp.escape(pattern).gsub("\\*\\*", ".*").gsub("\\*", "[^:]*") + "\\z",
        )

        re.match?(event)
      end
    end
  end
end
