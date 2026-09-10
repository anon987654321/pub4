# frozen_string_literal: true

require_relative "test_helper"
require "review/scan/rule_dsl"
require_relative "../tools/rule_reach"

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
  end

  # Adherence used to average registry coverage against a term that read
  # `(wired + unwired) / (wired + unwired)`, so it could not fall below 55 and
  # SelfTest's "below 35 is a violation" check could not fire. An empty registry
  # is the input that proves the floor is gone.
  def test_adherence_can_reach_zero
    empty = audit.call.with(mechanical: [])

    assert_in_delta 0.0, empty.adherence_pct
  end

  # Three gate banners and tools/rule_reach.rb print a count of one population,
  # and they read 107 and 115 for as long as one of them subtracted rather than
  # counted. Both directions: the shared answer, and that it is not the
  # subtraction that used to stand in for it.
  def test_coverage_agrees_with_rule_reach
    report = audit.call
    reach = Operator::RuleReach.mechanical(Operator::RuleReach.rules).size

    assert_equal reach, report.mechanical.size
    assert_includes report.coverage_line, "#{reach} of #{report.yaml_rules}"
    refute_equal report.yaml_rules - report.semantic_only.size, report.mechanical.size,
                 "the subtraction and the count agree here only by accident; if they " \
                 "have converged, say so rather than deleting the guard"
  end

  # A rule with a semantic prompt beside a law detector belongs to both
  # populations, which is why the subtraction was wrong in the first place.
  def test_a_rule_can_be_semantic_and_mechanical_at_once
    report = audit.call

    assert_includes report.semantic_only, "FAIL_VISIBLY"
    assert_includes report.mechanical, "FAIL_VISIBLY"
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

  # The escape hatch is idle: no rule declares a detect_lexical, so
  # YamlDeclarativeRule bridges nothing. This is the tripwire — the day somebody
  # declares one, it fails and asks whether the bridge is still wanted.
  def test_the_lexical_hatch_is_empty
    report = audit.call

    assert_empty report.lexical_wired
    assert_empty report.lexical_unwired
  end
end
