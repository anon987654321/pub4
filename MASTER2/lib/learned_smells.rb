# frozen_string_literal: true

require "json"

module MASTER
  # Persists project-specific smells discovered during sessions.
  # Smells accumulate in data/learned_smells.json and are injected into detection prompts.
  module LearnedSmells
    DATA_PATH = File.join(__dir__, "..", "data", "learned_smells.json").freeze

    module_function

    def all
      return [] unless File.exist?(DATA_PATH)
      JSON.parse(File.read(DATA_PATH), symbolize_names: true)
    rescue JSON::ParserError
      []
    end

    def add(smell)
      return if smell.nil? || smell.to_s.strip.empty?
      existing = all
      return if existing.any? { |s| s[:pattern].to_s == smell.to_s }
      existing << { pattern: smell.to_s, added_at: Time.now.utc.iso8601 }
      FileUtils.mkdir_p(File.dirname(DATA_PATH))
      File.write(DATA_PATH, JSON.pretty_generate(existing))
    end

    def to_prompt_fragment
      smells = all
      return "" if smells.empty?
      "Project-specific smells to also check:\n" + smells.map { |s| "  - #{s[:pattern]}" }.join("\n")
    end
  end
end
