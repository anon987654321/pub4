# frozen_string_literal: true

module Master
  # Explains the chain Law -> rule -> fix -> evidence for a given finding/commit.
  # Reads schema from data/why_command.yml.
  class WhyExplainer
    def initialize(rules_path: File.join(Master::ROOT, "data", "rules.yml"))
      @rules = Master.load_yaml(rules_path) || {}
      @laws  = (@rules["laws"] || []).each_with_index.to_h { |l, i| [l["id"], i + 1] }
    end

    def explain(rule_id:, fix_summary: nil, evidence_score: nil, vote_record: nil)
      rule = find_rule(rule_id)
      return Result.err("why: rule #{rule_id} not found", category: :validation) unless rule

      law_id   = rule["law"] || rule["anchor_law"] || "unanchored"
      law_rank = @laws[law_id] || "?"

      Result.ok([
        "rule fired:        #{rule_id}",
        "anchored to law:   #{law_id} (rank #{law_rank})",
        "fix applied:       #{fix_summary || '(none recorded)'}",
        "evidence:          #{evidence_score || '?'}/100",
        "council vote:      #{vote_record || '(no vote)'}",
      ].join("\n"))
    end

    private

    def find_rule(rule_id)
      (@rules["rules"] || {}).values.flatten.find { |r| r["id"].to_s == rule_id.to_s }
    end
  end
end
