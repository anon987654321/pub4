# frozen_string_literal: true

require_relative "test_helper"
require "review/scan/rule_dsl"

class TestRuleRegistryAudit < Minitest::Test
  # Defined here on purpose: Rule.inherited registers every subclass in the
  # process, so this class is in the registry the moment this file loads. It is
  # the shape that made rule_deps.ungraphed read 133 alone and 135 under
  # `rake test` — a census answering a different number depending on what else
  # the process had run.
  class RuleDefinedByATest < Master::Review::Scan::Rule
    def initialize
      super
      @id = "rule_defined_by_a_test"
    end

    def check(_code, path:) = []
  end

  def audit = Master::Review::Scan::RuleRegistryAudit.new(root: Master::ROOT)

  def test_audit_reports_yaml_and_registry_counts
    report = audit.call
    assert_operator report.yaml_rules, :>, 100
    assert_operator report.registry_ids.size, :>, 50
    assert_operator report.adherence_pct, :>, 20.0
    assert report.lines.join.include?("rules audit")
  end

  def test_ungraphed_rules_is_enumerable
    assert_kind_of Array, audit.ungraphed_rule_ids
  end

  def test_a_rule_a_test_defined_is_not_in_the_corpus
    assert_includes Master::Review::Scan::Rule.registry, RuleDefinedByATest,
                    "the premise: defining the class registers it"

    refute_includes audit.ungraphed_rule_ids, "rule_defined_by_a_test"
    refute_includes audit.call.registry_ids, "rule_defined_by_a_test"
  end

  # The counterweight: excluding tests must not exclude the shipped rules, which
  # is how a census gets quiet instead of correct.
  def test_the_shipped_rules_are_still_counted
    ids = audit.call.registry_ids

    assert_operator ids.size, :>, 100
    assert_includes ids, "trailing_whitespace"
    assert_includes ids, "no_god_class"
  end
end
