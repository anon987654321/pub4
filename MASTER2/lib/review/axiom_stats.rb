# frozen_string_literal: true

module MASTER
  module Review
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
        # MASTER.root points to the MASTER2 directory when running from within MASTER2
        # or to pub4 directory when running from outside
        axioms_paths = [
          File.join(MASTER.root, "data", "axioms.yml"),              # When run from MASTER2
          File.join(MASTER.root, "MASTER2", "data", "axioms.yml")   # When run from pub4
        ]

        axioms_file = axioms_paths.find { |path| File.exist?(path) }

        return [] unless axioms_file

        begin
          YAML.safe_load_file(axioms_file) || []
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
end
