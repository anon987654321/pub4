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

      # Publish an event whose durable record is a precondition for proceeding.
      # Unlike ordinary telemetry, persistence failure raises to the caller.
      # Subscribers still run through the shared bounded dispatch queue.
      def publish_required(event, payload = {})
        conversation = Fiber[:master_conversation]
        enriched = payload.merge(event:, ts: elapsed_ms)
        enriched[:conversation] = conversation if conversation
        persist_required_event(event, enriched)

        state = Thread.current.thread_variable_get(:master_event_dispatch)
        unless state
          state = { queue: [], dispatched: 0, warned: false }
          Thread.current.thread_variable_set(:master_event_dispatch, state)
          begin
            enqueue(state, event, enriched, conversation:, already_persisted: true)
            drain(state)
          ensure
            Thread.current.thread_variable_set(:master_event_dispatch, nil)
          end
          return self
        end

        enqueue(state, event, enriched, conversation:, already_persisted: true)
        self
      end

      private

      # Handlers are allowed to publish follow-up events, but those events are
      # queued rather than recursively calling publish -> handler -> publish.
      # The queue is per thread, so independent model/tool workers still publish
      # normally. A bounded cascade prevents a broken telemetry handler from
      # generating an unbounded stream of its own error event.
      def enqueue(state, event, payload, conversation: Fiber[:master_conversation], already_persisted: false)
        if state[:dispatched] + state[:queue].size >= MAX_DISPATCHED_EVENTS
          warn_dispatch_limit(state, event)
          return
        end

        state[:queue] << [event, payload, conversation, already_persisted]
      end

      def drain(state)
        until state[:queue].empty?
          event, payload, conversation, already_persisted = state[:queue].shift
          state[:dispatched] += 1
          dispatch_one(event, payload, conversation, already_persisted:)
        end
      end

      def dispatch_one(event, payload, conversation, already_persisted: false)
        ts = elapsed_ms
        # One process-wide bus. ChatService (and anything else that writes a
        # visitor's SSE from a handler) must be able to ignore another
        # conversation's events — without this stamp, subscribe("**") and even
        # named tool:before handlers dump visitor B's turn into visitor A's stream.
        if already_persisted
          enriched = payload
        else
          enriched = payload.merge(event:, ts:)
          enriched[:conversation] = conversation if conversation
        end
        handlers = synchronize { matching_handlers(event) }

        persist_event(event, enriched) unless already_persisted

        previous_conversation = Fiber[:master_conversation]
        Fiber[:master_conversation] = conversation
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
      ensure
        Fiber[:master_conversation] = previous_conversation
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

        Master::Trace::Dmesg.once("event0", "#{key} failed, #{error.class}: #{error.message}")
      rescue StandardError
        nil
      end

      def warn_dispatch_limit(state, event)
        return if state[:warned]

        state[:warned] = true
        Master::Trace::Dmesg.once("event0", "dispatch limit #{MAX_DISPATCHED_EVENTS} reached at #{event}, dropping recursive telemetry")
      rescue StandardError
        nil
      end

      def persist_required_event(event, payload)
        safe_payload = persisted_payload(event, payload)
        append_required(@event_log, event, safe_payload)
        if @evidence_log&.operational?(event)
          append_required(@evidence_log, event, safe_payload)
        end
      rescue StandardError => e
        raise IOError, "required event persistence failed for #{event}: #{e.class}: #{e.message}"
      end

      def append_required(log, event, payload)
        unless log.respond_to?(:append!)
          raise IOError, "event log does not support required persistence"
        end

        result = log.append!(event, payload)
        raise IOError, "event log rejected #{event}" if result.nil?

        result
      end

      def persist_event(event, payload)
        safe_payload = persisted_payload(event, payload)
        @event_log.append(event, safe_payload)
        @evidence_log&.append(event, safe_payload) if @evidence_log&.operational?(event)
      rescue StandardError => e
        warn_failure("persist #{event}", e)
      end

      # Persisted events are shared across sessions and survive the process.
      # Keep raw tool payloads on the live dispatch path for policy handlers, but
      # write only bounded metadata to the durable event and evidence logs.
      def persisted_payload(event, payload)
        name = event.to_s
        value = if name == "core:reason" || name.start_with?("tool:", "fix:transaction", "fix_loop:", "fix:journal", "fix:start", "fix:resume", "fix:interrupted", "ops:commit")
                  lifecycle_payload(payload)
                else
                  Master::Ground::Redactor.payload(payload)
                end
        # The conversation value may be a bearer cookie. Log::Event already
        # records a non-reversible session digest, so the raw value is redundant.
        value.reject { |key, _| key.to_s == "conversation" }
      end

      SAFE_LIFECYCLE_LABELS = %w[
        event tool operation verb capability stage phase status category result_state
        reason_code code effect_id parent_effect_id checkpoint_id transaction_id audit_id
        run_id subject_type subject_id commit head_before head_after target boundary
        previous_state state
      ].freeze

      SAFE_LIFECYCLE_COUNTS = %w[
        turn elapsed_ms duration_ms tracked_paths path_count finding_count argument_count
        file_count count attempt tries resume_count remaining_seconds output_bytes output_lines
        input_bytes input_lines bytes lines violations changes additions deletions
      ].freeze

      def lifecycle_payload(payload)
        safe = {}
        payload.each do |raw_key, value|
          key = raw_key.to_s
          case key
          when "conversation"
            next
          when "path"
            safe[:path_present] = !value.to_s.empty?
          when "paths"
            safe[:path_count] = Array(value).size
          when "argv", "args"
            safe[:argument_count] = value.is_a?(Hash) ? value.size : Array(value).size
          when "findings"
            safe[:finding_count] = Array(value).size
          when "why", "reason", "message", "detail", "summary", "content", "text", "prompt", "output", "error", "stderr", "stdout"
            next if value.nil? || value.to_s.empty?

            label = {
              "why" => :reason_present, "reason" => :reason_present,
              "message" => :message_present, "detail" => :detail_present,
              "summary" => :summary_present, "content" => :content_present,
              "text" => :text_present, "prompt" => :prompt_present,
              "output" => :output_present, "error" => :error_present,
              "stderr" => :stderr_present, "stdout" => :stdout_present,
            }.fetch(key)
            safe[label] = true
            safe["#{label.to_s.delete_suffix("_present")}_bytes".to_sym] = value.to_s.bytesize
          else
            symbol = key.to_sym
            if SAFE_LIFECYCLE_COUNTS.include?(key) && (value.is_a?(Numeric) || value == true || value == false)
              safe[symbol] = value
            elsif SAFE_LIFECYCLE_LABELS.include?(key) && value.is_a?(String) &&
                  value.match?(/\A[a-zA-Z0-9_.:\/-]{1,128}\z/)
              safe[symbol] = value
            elsif SAFE_LIFECYCLE_LABELS.include?(key) && value.is_a?(Symbol)
              safe[symbol] = value.to_s
            elsif SAFE_LIFECYCLE_LABELS.include?(key) && (value.is_a?(Numeric) || value == true || value == false)
              safe[symbol] = value
            end
          end
        end
        Master::Ground::Redactor.payload(safe)
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
