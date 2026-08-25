# frozen_string_literal: true

require_relative "test_helper"
# See test_adversarial_rule: SemanticRule lives in a plural rules file and is
# reached by require, never by autoload.
require "review/scan/rules/semantic_rules"

class TestFindingMetadata < Minitest::Test
  def test_finding_exposes_rule_id_and_schema_metadata
    finding = Master::Review::Scan::Finding.build(
      rule: "SECRET_PROXIMITY",
      message: "hardcoded secret",
      line: 4,
      reversibility: "cheap",
      blast_radius: { "files_touched" => 1 },
    )

    assert_equal "SECRET_PROXIMITY", finding.rule
    assert_equal "SECRET_PROXIMITY", finding.rule_id
    assert_equal "cheap", finding.reversibility
    assert_equal({ "files_touched" => 1 }, finding.blast_radius)
    assert_equal "SECRET_PROXIMITY", finding.to_h[:rule_id]
  end

  def test_semantic_findings_keep_exact_rule_id
    rule = Master::Review::Scan::Rules::SemanticRule.new
    rule.instance_variable_set(:@rules, {
      "PATTERN_EXTRACTION" => {
        severity: :info,
        mode: :opportunity,
        reversibility: "surgical",
        blast_radius: { "files_touched" => 2 },
      },
    })

    findings = rule.send(:parse_findings, "PATTERN_EXTRACTION:12:extract strategy")

    assert_equal 1, findings.size
    assert_equal "PATTERN_EXTRACTION", findings.first.rule_id
    assert_equal "PATTERN_EXTRACTION", findings.first.rule
    assert_equal "surgical", findings.first.reversibility
    assert_equal({ "files_touched" => 2 }, findings.first.blast_radius)
  end
end
