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
    # The scope the file was asked about, which is what parse_findings reads: a
    # reply naming a rule outside it is one the model invented for this file.
    scoped = {
      "PATTERN_EXTRACTION" => {
        severity: :info,
        mode: :opportunity,
        reversibility: "surgical",
        blast_radius: { "files_touched" => 2 },
        languages: ["ruby"],
      },
    }

    findings = rule.send(:parse_findings, "PATTERN_EXTRACTION:12:extract strategy", scoped)

    assert_equal 1, findings.size
    assert_equal "PATTERN_EXTRACTION", findings.first.rule_id
    assert_equal "PATTERN_EXTRACTION", findings.first.rule
    assert_equal "surgical", findings.first.reversibility
    assert_equal({ "files_touched" => 2 }, findings.first.blast_radius)
  end
end

# Finding.read is the one accessor for the shape trap AGENTS.md records: a
# rule answers a Finding, scan_dir answers plain symbol-keyed Hashes, and four
# readers each hand-rolled the same ladder. Every shape it is asked about is
# pinned here, including the two that used to be handled by different halves
# of that ladder.
class TestFindingRead < Minitest::Test
  F = Master::Review::Scan::Finding

  def finding = F.build(rule: "NO_DEBUG", message: "binding.pry", line: 7)

  def test_reads_a_finding_object
    assert_equal "NO_DEBUG", F.read(finding, :rule)
    assert_equal 7, F.read(finding, :line)
    assert_equal "binding.pry", F.read(finding, :message)
  end

  def test_reads_the_plain_hash_scan_dir_returns
    row = { rule: "NO_PUTS", message: "puts", line: 3 }

    assert_equal "NO_PUTS", F.read(row, :rule)
    assert_equal 3, F.read(row, :line)
  end

  # A bare Data.define with no #[] is what a test double usually is, and
  # reading only the subscript returned nil for one without failing.
  def test_reads_an_object_that_answers_the_method_but_not_the_subscript
    double = Data.define(:rule, :line).new(rule: "FROZEN_LITERAL", line: 1)

    assert_equal "FROZEN_LITERAL", F.read(double, :rule)
  end

  # A reporter must not be the thing that fails on a rule returning nonsense.
  def test_answers_nil_for_a_shape_it_cannot_read
    assert_nil F.read(Object.new, :rule)
    assert_nil F.read(nil, :rule)
  end

  def test_a_hash_missing_the_key_is_nil_not_an_error
    assert_nil F.read({ message: "no rule here" }, :rule)
  end
end
