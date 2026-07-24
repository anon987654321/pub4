# frozen_string_literal: true

module Master
  module Fix
    # Single ranking primitive shared by RuleOrder (which rule to fix next)
    # and ConflictResolver (whether a fix's side effect is bad enough to
    # reject). Replaces BiasGuard#priority_score (RuleOrder's prior use) and
    # a plain Severity.rank comparison (ConflictResolver's prior use) with
    # one formula that also weighs constitutional law priority and learned
    # fix quality, so both call sites agree on what "more important" means.
    module Priority
      module_function

      def score(rule_id:, severity:, frequency: 1.0, age_days: 0.0,
                law_resolver: nil, rules_index: nil, quality: 0.5, tier2: false)
        sev = Master::SEVERITY_RANK.fetch(severity.to_sym, 1)
        law_p = law_resolver ? law_resolver.priority(law_resolver.law_for(rule_id, rules_index:)) : 50
        # Invert law priority so a lower law number (more foundational) scores higher.
        law_component = (100 - law_p).clamp(0, 100)
        density = sev * frequency.to_f * (1.0 + (age_days.to_f / 30.0))
        base = density + (law_component * 0.5) + (quality.to_f * 2.0)
        tier2 ? base + 50.0 : base
      end

      # True when +candidate+ outranks +baseline+. Both are score() kwarg hashes.
      def higher?(candidate, baseline)
        score(**candidate) > score(**baseline)
      end

      # Shared with ConflictResolver's prior private #build_rules_index --
      # both need the same rule_id => rule_entry map to resolve law_for.
      def rules_index(root:)
        Master.flatten_rules(Master.load_rules(root:).fetch("rules", {}))
          .each_with_object({}) do |entry, index|
            next unless entry.is_a?(Hash) && entry["id"]

            index[entry["id"].to_s] = entry
          end
      end
    end
  end
end
