# frozen_string_literal: true

require_relative "test_helper"

class TestConstitutionTriage < Minitest::Test
  def test_buckets_scanner_self_and_rule_retune_findings
    triage = Master::Review::Scan::ConstitutionTriage.new(root: Master::ROOT)
    findings = [
      { rule: "SILENT_RESCUE", file: File.join(Master::ROOT, "lib/ground/config.rb") },
      { rule: "magic_number", file: File.join(Master::ROOT, "lib/ground/config.rb") },
      { rule: "SQL_INJECTION", file: File.join(Master::ROOT, "lib/review/scan/rules/yaml_bridge_rules.rb") },
      { rule: "SCAN_TIMEOUT", file: File.join(Master::ROOT, "lib/slow.rb") },
    ]

    buckets = triage.buckets(findings).to_h { |bucket| [bucket.name, bucket.findings.size] }

    assert_equal 1, buckets[:true_violation]
    assert_equal 1, buckets[:rule_retune]
    assert_equal 1, buckets[:scanner_self_reference]
    assert_equal 1, buckets[:timed_out]
  end
end
