# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "time"

module Master
  module Trace
    class EventLog
      DEFAULT_STREAM = "activity"
      STREAM_PATTERN = /\A[a-z0-9_\-]+\z/

      attr_reader :path

      def initialize(root: Master::ROOT, stream: DEFAULT_STREAM)
        @root = root
        @stream = normalize_stream(stream)
        @path = File.join(@root, "runtime", "events", "#{@stream}.jsonl")
      end

      def append(event, payload = {})
        record = build_record(event, payload)
        FileUtils.mkdir_p(File.dirname(@path))
        File.open(@path, "a") { |io| io.write(JSON.generate(record), "\n") }
        record
      rescue SystemCallError, JSON::GeneratorError => e
        # Stderr is last resort — cannot route through bus without risking recursion.
        Kernel.warn("event_log: append to #{@path} failed — #{e.class}: #{e.message}")
        nil
      end

      # O203: shared JSONL reader for recent_events and dispatch_tail.
      def read_lines
        return [] unless File.exist?(@path)

        File.foreach(@path).to_a
      rescue StandardError
        []
      end

      def recent(n, now: Time.now.utc)
        read_lines.last(n).filter_map do |line|
          rec = JSON.parse(line) rescue next
          ts = (Time.parse(rec["timestamp"]) rescue now)
          secs = (now - ts).to_i.abs
          ago = secs < 60 ? "#{secs}s" : (secs < 3600 ? "#{secs / 60}m" : "#{secs / 3600}h")
          pay = rec["payload"]
          sum = pay.is_a?(Hash) ? pay.first(3).map { |k, v| "#{k}=#{v.to_s.tr('"', "")[0, 24]}" }.join(" ") : pay.to_s
          { ago: ago.rjust(4), event: rec["event"].to_s, summary: sum[0, 80] }
        end
      end

      def tail(n, pattern: nil)
        lines = read_lines
        rx = pattern && !pattern.empty? ? Regexp.new(pattern) : nil
        lines = lines.select { |l| l.include?(pattern) } if rx && pattern.match?(/\A[a-z0-9_:.-]+\z/i)
        lines.last(n).filter_map do |line|
          rec = JSON.parse(line) rescue next
          next if rx && !rec["event"].to_s.match?(rx)
          rec
        end
      end

      private

      def build_record(event, payload)
        now = Time.now.utc
        {
          id: SecureRandom.uuid,
          timestamp: now.iso8601(6),
          event: event.to_s,
          payload: payload || {}
        }
      end

      def normalize_stream(stream)
        candidate = stream.to_s
        candidate.match?(STREAM_PATTERN) ? candidate : DEFAULT_STREAM
      end
    end
  end
end
