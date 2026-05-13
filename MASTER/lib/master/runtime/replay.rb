# frozen_string_literal: true

require "json"

module Master
  module Runtime
    class Replay
      DEFAULT_STREAM = "activity"

      def initialize(root: Master::ROOT)
        @root = root
      end

      def events(stream: DEFAULT_STREAM, limit: nil)
        path = stream_path(stream)
        return [] unless File.file?(path)

        records = File.readlines(path, chomp: true).filter_map { |line| parse_line(line) }
        limit ? records.last(limit) : records
      rescue SystemCallError
        []
      end

      def workflows(workflow_id)
        events.select do |record|
          payload = record.fetch("payload", {})
          payload["workflow_id"].to_s == workflow_id.to_s
        end
      end

      def summarize(stream: DEFAULT_STREAM)
        events(stream:).each_with_object(Hash.new(0)) do |record, counts|
          counts[record.fetch("event", "unknown")] += 1
        end.sort.to_h
      end

      private

      def stream_path(stream)
        safe_stream = stream.to_s.gsub(/[^a-zA-Z0-9_\-]/, "")
        File.join(@root, "runtime", "events", "#{safe_stream}.jsonl")
      end

      def parse_line(line)
        JSON.parse(line)
      rescue JSON::ParserError
        nil
      end
    end
  end
end
