# frozen_string_literal: true
require "json"

module Master
  # Pattern library — durable lessons with success-rate weights.
  # Persists to .master_patterns.json (gitignored). Source: master.json v225 #22.
  class LearningsPatternLib
    STORE = ".master_patterns.json"
    DEPRECATE_BELOW = 0.30

    def initialize(root: Master::ROOT)
      @path = File.join(root, STORE)
      @data = load
    end

    def record(pattern:, context:, solution:, outcome:)
      entry = @data[pattern] ||= {context:, solution:, weight: 0.5, hits: 0, examples: []}
      entry[:hits] += 1
      entry[:weight] = outcome == :success ? [entry[:weight] + 0.05, 1.0].min : [entry[:weight] - 0.10, 0.0].max
      entry[:context] = context
      entry[:solution] = solution
      save
    end

    def lookup(pattern)
      entry = @data[pattern]
      return nil unless entry && entry[:weight] >= DEPRECATE_BELOW
      entry
    end

    def deprecate_low_weight
      @data.reject! { |_, e| e[:weight] < DEPRECATE_BELOW }
      save
    end

    private

    def load
      return {} unless File.exist?(@path)
      JSON.parse(File.read(@path), symbolize_names: true)
    rescue JSON::ParserError
      {}
    end

    def save
      File.write(@path, JSON.pretty_generate(@data))
    end
  end
end
