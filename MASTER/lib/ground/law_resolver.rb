# frozen_string_literal: true

module Master
  module Ground
    # Resolves rule conflicts using rules.yml laws: priority (lower wins).
    class LawResolver
      def initialize(rules_data: nil)
        @laws = (rules_data || Master.load_yaml(Master::RULES_PATH).fetch("laws", {}))
                  .transform_values { |v| v["priority"].to_i }
                  .sort_by { |_, priority| priority }
                  .to_h
      end

      def law_for(rule_id, rules_index: nil)
        entry = rules_index&.dig(rule_id.to_s.upcase) || rules_index&.dig(rule_id.to_s)
        return unless entry

        tags = Array(entry["violates_law"] || entry["supports_law"] || infer_law(entry))
        tags.first
      end

      def winner(rule_a, rule_b, rules_index: nil)
        law_a = priority(law_for(rule_a, rules_index:))
        law_b = priority(law_for(rule_b, rules_index:))
        return rule_a if law_a < law_b
        return rule_b if law_b < law_a

        rule_a
      end

      def priority(law_name)
        @laws.fetch(law_name.to_s, 99)
      end

      private

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
