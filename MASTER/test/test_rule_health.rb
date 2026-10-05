# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/review/scan/rule_health"
require_relative "../lib/fix/protocol_detector_matrix"

class TestRuleHealth < Minitest::Test
  Rule = Struct.new(:id, :severity)

  def test_measurement_only_rules_are_visible_but_not_blocking
    rule = Rule.new("CQS", :warning)

    assert Master::Review::Scan::RuleHealth.measurement_mode?(rule)
    assert_equal :measurement, Master::Review::Scan::RuleHealth.enforcement(rule)

    finding = { rule: "CQS", severity: :warning, tags: [:CQS] }
    annotated = Master::Review::Scan::RuleHealth.annotate(finding)

    assert_equal :warning, annotated[:original_severity]
    assert_equal :info, annotated[:severity]
    assert_equal "measurement", annotated[:enforcement]
    assert_includes annotated[:tags], :MEASUREMENT_ONLY
  end

  def test_non_calibrated_rules_keep_their_severity_and_enforcement
    warning = Rule.new("LONG_METHOD", :warning)
    error = Rule.new("PATH_PURPOSE", :error)

    refute Master::Review::Scan::RuleHealth.measurement_mode?(warning)
    assert_equal :advisory, Master::Review::Scan::RuleHealth.enforcement(warning)
    assert_equal :blocking, Master::Review::Scan::RuleHealth.enforcement(error)

    finding = { rule: "LONG_METHOD", severity: :warning }
    assert_equal finding, Master::Review::Scan::RuleHealth.annotate(finding)
  end

  def test_matrix_calibration_has_a_reason
    matrix = Master::Fix::ProtocolDetectorMatrix.matrix([Rule.new("CQS", :warning)])
    row = matrix.fetch("CQS")

    assert_equal true, row.fetch("measurement_mode")
    assert_equal "measurement", row.fetch("enforcement")
    refute_empty row.fetch("calibration").fetch("reason")
  end
end
