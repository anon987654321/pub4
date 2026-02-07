# frozen_string_literal: true

require "yaml"

module MASTER
  # AxiomStats - Provides statistics and summary views for language axioms
  module AxiomStats
    extend self

    def stats
      axioms = load_axioms
      
      return { error: "No axioms found" } if axioms.empty?

      {
        total: axioms.size,
        by_category: count_by_key(axioms, "category"),
        by_protection: count_by_key(axioms, "protection"),
        axioms: axioms
      }
    end

    def summary
      data = stats
      return data if data[:error]

      lines = []
      lines << "Language Axioms Summary"
      lines << "=" * 40
      lines << ""
      lines << "Total axioms: #{data[:total]}"
      lines << ""
      lines << "By Category:"
      data[:by_category].sort_by { |_, count| -count }.each do |category, count|
        lines << "  #{category.ljust(20)} #{count}"
      end
      lines << ""
      lines << "By Protection Level:"
      data[:by_protection].sort_by { |_, count| -count }.each do |protection, count|
        lines << "  #{protection.ljust(20)} #{count}"
      end
      lines << ""
      
      lines.join("\n")
    end

    def top_categories(limit: 5)
      data = stats
      return [] if data[:error]
      
      data[:by_category].sort_by { |_, count| -count }.first(limit)
    end

    private

    def load_axioms
      axioms_file = File.join(MASTER.root, "MASTER2", "data", "axioms.yml")
      
      return [] unless File.exist?(axioms_file)
      
      begin
        YAML.load_file(axioms_file) || []
      rescue => e
        []
      end
    end

    def count_by_key(axioms, key)
      counts = Hash.new(0)
      axioms.each do |axiom|
        value = axiom[key]
        counts[value] += 1 if value
      end
      counts
    end
  end
end
