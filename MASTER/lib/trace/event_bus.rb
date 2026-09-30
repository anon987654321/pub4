# frozen_string_literal: true

require "monitor"

module Master
  module Trace
    # Not wisper: this bus matches topics by glob, redacts what it persists,
    # stamps each event with the Fiber's conversation and wraps delivery in a
    # telemetry span, where wisper broadcasts to listeners.
    class EventBus
      include MonitorMixin

      BOOT_TIME = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
      PATTERN_CACHE_MAX = 512
      MAX_DISPATCHED_EVENTS = 64
      FAILURE_WARNING_LIMIT = 8

      def initialize(event_log: nil, evidence_log: nil)
        super()
        @subscribers = Hash.new { |h, k| h[k] = [] }
        @pattern_cache = {}
        @event_log = event_log || Master::Trace::Log::Event.new
        @evidence_log = evidence_log
        @failure_mutex = Mutex.new
        @failure_warnings = {}
      end

      def subscribe(pattern, &handler)
        synchronize { @subscribers[pattern] << handler }
        -> { synchronize { @subscribers[pattern].delete(handler) } }
      end

      def publish(event, payload = {})
        state = Thread.current.thread_variable_get(:master_event_dispatch)
        unless state
          state = { queue: [], dispatched: 0, warned: false }
          Thread.current.thread_variable_set(:master_event_dispatch, state)
          begin
            enqueue(state, event, payload)
            drain(state)
          ensure
            Thread.current.thread_variable_set(:master_event_dispatch, nil)
          end
          return self
        end

        enqueue(state, event, payload)
        self
      end

      private

      # Handlers are allowed to publish follow-up events, but those events are
      # queued rather than recursively calling publish -> handler -> publish.
      # The queue is per thread, so independent model/tool workers still publish
      # normally. A bounded cascade prevents a broken telemetry handler from
      # generating an unbounded stream of its own error event.
      def enqueue(state, event, payload)
        if state[:dispatched] + state[:queue].size >= MAX_DISPATCHED_EVENTS
          warn_dispatch_limit(state, event)
          return
        end

        state[:queue] << [event, payload, Fiber[:master_conversation]]
      end

      def drain(state)
        until state[:queue].empty?
            event, payload, conversation = state[:queue].shift
          state[:dispatched] += 1
          dispatch_one(event, payload, conversation)
        end
      end

      def dispatch_one(event, payload, conversation)
        ts = elapsed_ms
        # One process-wide bus. ChatService (and anything else that writes a
        # visitor's SSE from a handler) must be able to ignore another
        # conversation's events — without this stamp, subscribe("**") and even
        # named tool:before handlers dump visitor B's turn into visitor A's stream.
        enriched = payload.merge(event:, ts:)
        enriched[:conversation] = conversation if conversation
        handlers = synchronize { matching_handlers(event) }

        persist_event(event, enriched)

        # No per-subscriber deadline. Ruby bounds a handler only by raising into
        # it at whatever line it reached, and the handlers are inline writers of
        # log lines and SSE frames that a raise mid-write leaves torn. A handler's
        # error is swallowed and its answer ignored, so no subscriber guards a
        # write and there is nothing to fail closed.
        Master::Trace::Telemetry.span("event_bus.publish", event:, n_handlers: handlers.size) do
          handlers.each do |h|
            h.call(enriched)
          rescue StandardError => e
            report_handler_failure(event, e)
          end
        end
      end

      def report_handler_failure(event, error)
        warn_failure("handler #{event}", error)
        return if event.to_s == "error:swallowed"

        Master::Ground::Swallow.log(error, context: "event_bus.handler", event:)
      rescue StandardError => e
        warn_failure("handler-report #{event}", e)
      end

      def warn_failure(key, error)
        should_warn = @failure_mutex.synchronize do
          next false if @failure_warnings.size >= FAILURE_WARNING_LIMIT && !@failure_warnings.key?(key)
          next false if @failure_warnings[key]

          @failure_warnings[key] = true
          true
        end
        return unless should_warn

        Kernel.warn("event_bus: #{key} failed — #{error.class}: #{error.message}")
      rescue StandardError
        nil
      end

      def warn_dispatch_limit(state, event)
        return if state[:warned]

        state[:warned] = true
        Kernel.warn("event_bus: dispatch limit #{MAX_DISPATCHED_EVENTS} reached at #{event}; dropping recursive telemetry")
      rescue StandardError
        nil
      end

      def persist_event(event, payload)
        safe_payload = Master::Ground::Redactor.payload(payload)
        @event_log.append(event, safe_payload)
        @evidence_log&.append(event, safe_payload) if @evidence_log&.operational?(event)
      rescue StandardError => e
        warn_failure("persist #{event}", e)
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
