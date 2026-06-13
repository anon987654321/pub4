# frozen_string_literal: true

require "json"

module Master
  class Learnings
    LEARNINGS_FILE = "learnings.jsonl"
    EVENTS_FILE = "events.jsonl"
    THRESHOLD = 3

    def initialize(root:)
      @root = root
    end

    def record(trigger:, strategy:, outcome:)
      append(LEARNINGS_FILE, "trigger" => trigger, "strategy" => strategy, "outcome" => outcome.to_s)
    end

    def search(query)
      load_jsonl(LEARNINGS_FILE)
        .select { |h| h["trigger"].to_s.include?(query) || h["strategy"].to_s.include?(query) }
        .reject { |h| h["outcome"] == "failed" }
    end

    def record_event(event_type:, dimension:)
      append(EVENTS_FILE, "event_type" => event_type.to_s, "dimension" => dimension.to_s)
    end

    def opportunities
      events = load_jsonl(EVENTS_FILE)
      [
        [:high_failure, "tool_failure"],
        [:repeated_correction, "user_correction"],
        [:provider_errors, "provider_error"],
      ].flat_map do |category, event_type|
        events.select { |e| e["event_type"] == event_type }
              .group_by { |e| e["dimension"] }
              .filter_map { |dim, list| { category:, dimension: dim, count: list.size } if list.size >= THRESHOLD }
      end
    end

    private

    def path(file)
      File.join(@root, file)
    end

    def append(file, data)
      File.open(path(file), "a") { |f| f.puts(JSON.generate(data)) }
    end

    def load_jsonl(file)
      return [] unless File.exist?(path(file))
        JSON.parse(line)
      rescue JSON::ParserError
        nil
      end
    end
  end
end
