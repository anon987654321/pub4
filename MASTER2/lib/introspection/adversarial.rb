# frozen_string_literal: true

require "yaml"

module Introspection
  module Paths
    def self.load_data_file(pathname)
      return {} unless pathname && File.exist?(pathname)

      YAML.safe_load(File.read(pathname), permitted_classes: [Symbol, Date, Time], aliases: true) || {}
    rescue Psych::SyntaxError
      {}
    end
  end

  module Adversarial
    JOIN_SEPARATOR = "\",\n            \""
    DEFAULT_SAMPLE_LIMIT = 50
    DEFAULT_JOIN_LIMIT = 10
    DEFAULT_MISSING = "∅"

    class Runner
      def initialize(model_class:, axioms_path:, sample_limit: DEFAULT_SAMPLE_LIMIT, join_limit: DEFAULT_JOIN_LIMIT)
        @model_class = model_class
        @axioms_path = axioms_path
        @sample_limit = sample_limit
        @join_limit = join_limit
      end

      def interrogate
        axioms = Paths.load_data_file(@axioms_path).fetch("axioms", [])
        return [] if axioms.empty?

        axioms.map { |axiom| check_axiom(axiom) }.compact
      end

      def check_axiom(axiom)
        axiom_hash = axiom.is_a?(Hash) ? axiom : {}
        axiom_name = axiom_hash.fetch("name", "unnamed axiom")

        target_column = axiom_hash.fetch("column", nil)
        association_name = axiom_hash.fetch("includes", nil)
        expected_value = axiom_hash.fetch("equals", nil)
        where_clause = axiom_hash.fetch("where", {})
        limit = axiom_hash.fetch("limit", @sample_limit)

        return nil if target_column.nil?

        relation = base_relation(where_clause, association_name)
        values = relation.limit(limit).pluck(target_column)

        mismatch = expected_value.nil? ? values.any?(&:nil?) : values.any? { |value| value != expected_value }
        return nil unless mismatch

        {
          name: axiom_name,
          model: @model_class.name,
          column: target_column.to_s,
          expected: expected_value,
          sample: format_values(values)
        }
      end

      private

      def base_relation(where_clause, association_name)
        relation = @model_class.all
        relation = relation.includes(association_name) if association_name
        relation = relation.where(where_clause) if where_clause.is_a?(Hash) && !where_clause.empty?
        relation
      end

      def format_values(values)
        compacted = Array(values).first(@join_limit).map { |value| value.nil? ? DEFAULT_MISSING : value.to_s }
        return compacted.first.to_s if compacted.length == 1

        "[\"#{compacted.join(JOIN_SEPARATOR)}\"]"
      end
    end
  end
end