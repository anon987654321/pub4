# frozen_string_literal: true

require "json"
require "fileutils"
require "digest"
require_relative "event_privacy"

module Master
  module Trace
  # Trace — captures all bus events for the current turn into a JSONL log
  # at .master/traces/YYYY-MM-DD.jsonl (local state, never data/ — a runtime
  # write target inside the law tree read as config). One turn record per line.
  # /why formats the last turn.
    class Recorder
      EVENT_PATTERNS = %w[gateway:* pipeline:* tool:after route:* council:* memo:* lint:* governor:*].freeze
      MAX_EVENTS_PER_TURN = 200
      KEEP_DAYS = 14

      def initialize(root:, event_bus:)
        @dir = File.join(root, ".master", "traces")
        @bus = event_bus
        @mutex = Mutex.new
        @current = nil
        @last = nil
        FileUtils.mkdir_p(@dir, mode: 0o700)
        subscribe
      end

      def last_turn = @last

      def pretty_last
        turn = @last || load_last_from_disk
        return "no trace recorded yet" unless turn

        lines = ["turn #{turn[:id]}  ts=#{turn[:start_ts]}  channel=#{turn[:channel]}"]
        message = turn.fetch(:message, "")
        shown = message.is_a?(Hash) ? "#{message[:bytes]} bytes, kept as a digest" : message.to_s[0, 100]
        lines << "  message: #{shown}"
        turn[:events].each do |ev|
          ms = ev[:ts_ms]
          name = ev[:event]
          detail = ev.except(:ts_ms, :event).reject { |_, v| v.nil? }
          lines << "  +#{ms.to_s.rjust(5)}ms  #{name}  #{detail.empty? ? "" : detail.inspect}"
        end
        lines.join("\n")
      end

      private

      def subscribe
        EVENT_PATTERNS.each { |pat| @bus.subscribe(pat) { |ev| record(ev) } }
      end

      def record(event)
        @mutex.synchronize do
          if event[:event] == "gateway:turn_start"
            @current = { id: event[:turn_id], start_ts: Time.now.to_i, channel: event[:channel],
                         message: event[:message], events: [], t0: event[:ts] }
            next
          end
          if @current && event[:event] == "gateway:turn_done"
            @current[:events] << relative(event)
            finalize(@current)
            @last = @current
            @current = nil
            next
          end
          next unless @current
          next if @current[:events].size >= MAX_EVENTS_PER_TURN
          @current[:events] << relative(event)
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "recorder.ingest")
      end

      def relative(ev)
        ts0 = @current.fetch(:t0, 0)
        ev.merge(ts_ms: (ev.fetch(:ts, 0)) - ts0).except(:ts)
      end

      # Disk gets what the event log gets: the same EventPrivacy transform, the message as a
      # digest and length, owner-only, two weeks kept. Subscribers see raw payloads, and this
      # wrote them as they came: chat text, tool URLs and queries, in 0644 daily files.
      # /why keeps the full turn in memory for the process that recorded it.
      def finalize(turn)
        path = File.join(@dir, "#{Time.now.strftime("%Y-%m-%d")}.jsonl")
        File.open(path, "a", 0o600) { |f| f.puts JSON.generate(persisted(turn)) }
        File.chmod(0o600, path)
        prune
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "recorder.finalize", path:)
      end

      def persisted(turn)
        message = turn[:message].to_s
        events = turn[:events].map do |event|
          EventPrivacy.persisted(event[:event].to_s, event.except(:event)).merge(event: event[:event])
        end
        turn.merge(message: { sha256: Digest::SHA256.hexdigest(message), bytes: message.bytesize }, events:)
      end

      def prune
        cutoff = Time.now - (KEEP_DAYS * 86_400)
        Dir.glob(File.join(@dir, "*.jsonl")).each { |file| File.delete(file) if File.mtime(file) < cutoff }
      end

      def load_last_from_disk
        files = Dir.glob(File.join(@dir, "*.jsonl")).sort
        return if files.empty?

        # Streamed rather than read whole: a day of turns can be a large file.
        last_line = File.foreach(files.last).inject(nil) { |_, line| line }
        last_line ? JSON.parse(last_line, symbolize_names: true) : nil
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "recorder.load_last_from_disk")
        nil
      end
    end
  end
end
