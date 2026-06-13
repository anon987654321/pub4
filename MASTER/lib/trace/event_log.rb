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

      private

      def build_record(event, payload)
        now = Time.now.utc
        {
          id: SecureRandom.uuid,
          timestamp: now.iso8601(6),
          event: event.to_s,
          payload: payload || {},
        }
      end

      def normalize_stream(stream)
        candidate = stream.to_s
        candidate.match?(STREAM_PATTERN) ? candidate : DEFAULT_STREAM
      end
    end
  end
end
