# frozen_string_literal: true

require_relative "test_helper"
require "master"
require_relative "../lib/fix/constitutional_check"

class TestConstitutionalCheck < Minitest::Test
  def test_admits_clean_when_no_findings
    assert Master::Fix::ConstitutionalCheck.admit_clean?([])
  end

  def test_blocks_constitutional_error
    findings = [{ severity: :error, tier: "constitutional", law_id: "ROBUSTNESS", message: "x" }]
    refute Master::Fix::ConstitutionalCheck.admit_clean?(findings)
    assert_equal 1, Master::Fix::ConstitutionalCheck.residual_errors(findings).size
  end

  def test_allows_warning_without_constitutional_tier
    findings = [{ severity: :warning, id: "style_nit" }]
    assert Master::Fix::ConstitutionalCheck.admit_clean?(findings)
  end

  def test_blocks_priority_law_id_even_without_tier_field
    findings = [{ severity: :error, law_id: "CAPABILITY_STATUS_MUST_BE_TRUTHFUL" }]
    refute Master::Fix::ConstitutionalCheck.admit_clean?(findings)
  end

  def test_veto_is_blocking
    findings = [{ severity: :veto, tier: "constitutional" }]
    refute Master::Fix::ConstitutionalCheck.admit_clean?(findings)
  end
end
