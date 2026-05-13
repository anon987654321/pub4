# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "time"

module Master
  module Runtime
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
      rescue SystemCallError, JSON::GeneratorError
        nil
      end

      private

      def build_record(event, payload)
        {
          id: SecureRandom.uuid,
          timestamp: Time.now.utc.iso8601(6),
          event: event.to_s,
          payload: payload || {}
        }
      end

      def normalize_stream(stream)
        candidate = stream.to_s
        return candidate if candidate.match?(STREAM_PATTERN)

        DEFAULT_STREAM
      end
    end
  end
end
