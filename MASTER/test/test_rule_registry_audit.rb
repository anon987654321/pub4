# frozen_string_literal: true

require_relative "test_helper"

class TestRuleRegistryAudit < Minitest::Test
  def test_audit_reports_yaml_and_registry_counts
    audit = Master::Judge::Scan::RuleRegistryAudit.new(root: Master::ROOT).call
    assert_operator audit.yaml_rules, :>, 100
    assert_operator audit.registry_ids.size, :>, 50
    assert_operator audit.adherence_pct, :>, 20.0
    assert audit.lines.join.include?("rules audit")
  end

  def test_ungraphed_rules_is_enumerable
    gaps = Master::Judge::Scan::RuleRegistryAudit.new(root: Master::ROOT).ungraphed_rule_ids
    assert gaps.is_a?(Array)
  end
end