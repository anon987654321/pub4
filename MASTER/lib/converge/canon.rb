# frozen_string_literal: true

module Converge
  class Canon
    class CyclicDependencyError < StandardError; end
    class MissingDependencyError < StandardError; end

    include TSort

    def self.load(path)
      raw = YAML.safe_load_file(path, permitted_classes: [Symbol], aliases: true)
      entries = normalize_entries(raw)
      new(entries).topologically_sorted
    end

    def self.normalize_entries(raw)
      rules = raw.fetch("rules")
      return rules if rules.is_a?(Array)

      rules.values.flat_map { |group| group.is_a?(Array) ? group : [] }
    end

    def initialize(entries)
      @rules = entries.map { |entry| Rule.new(entry) }
      @rule_map = @rules.to_h { |rule| [rule.id, rule] }
      validate_dependencies!
    end

    def topologically_sorted
      tsort
    rescue TSort::Cyclic => error
      raise CyclicDependencyError, "cycle detected: #{error.message}"
    end

    def tsort_each_node(&block)
      @rules.each(&block)
    end

    def tsort_each_child(rule, &block)
      rule.depends_on.each { |dependency| block.call(@rule_map.fetch(dependency)) }
    end

    private

    def validate_dependencies!
      missing = @rules.flat_map(&:depends_on).uniq - @rule_map.keys
      return if missing.empty?

      raise MissingDependencyError, "missing rule dependencies: #{missing.join(", ")}"
    end
  end
end
