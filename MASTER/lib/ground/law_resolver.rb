# frozen_string_literal: true

module Master
  module Ground
    # Resolves Law conflicts using the constitutional priority entries in
    # laws.yml (lower priority number wins).
    #
    # The current schema stores the eight governing Laws at top level;
    # the loader also accepts a { "laws" => ... } section when supplied explicitly.
    class LawResolver
      def initialize(laws_data: nil)
        data = laws_data || Master.load_yaml(Master::LAWS_PATH)
        @laws = law_entries(data)
          .transform_values { |value| value["priority"].to_i }
          .sort_by { |_, priority| priority }
          .to_h
      end

      def law_for(law_id, laws_index: nil)
        entry = laws_index&.dig(law_id.to_s.upcase) || laws_index&.dig(law_id.to_s)
        return unless entry

        tags = Array(entry["violates_law"] || entry["supports_law"] || infer_law(entry))
        tags.first
      end

      def winner(law_a, law_b, laws_index: nil)
        priority_a = priority(law_for(law_a, laws_index:))
        priority_b = priority(law_for(law_b, laws_index:))
        return law_a if priority_a < priority_b
        return law_b if priority_b < priority_a

        law_a
      end

      def priority(law_name)
        @laws.fetch(law_name.to_s, 99)
      end

      private

      def law_entries(data)
        wrapped = data["laws"]
        return wrapped if wrapped.is_a?(Hash)

        data.select do |name, value|
          name.to_s.match?(/\A[A-Z][A-Z0-9_]*\z/) &&
            value.is_a?(Hash) &&
            value["priority"] &&
            (value["statement"] || value["name"])
        end
      end

      def infer_law(entry)
        tier = entry["tier"].to_s
        case tier
        when "kernel", "safety", "reliability", "performance", "security", "robustness",
             "correctness", "verification" then "ROBUSTNESS"
        when "clean_code", "style", "density", "clarity", "aesthetic" then "DENSITY"
        when "architecture", "design", "solid", "interface" then "ABSTRACTION"
        else "DENSITY"
        end
      end
    end
  end
end
