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

  def test_priority_law_ids_come_from_the_canonical_law_reader
    expected = Master.law_entries(root: Master::ROOT).filter_map do |entry|
      next unless entry["tier"].to_s == "constitutional"
      next unless entry.key?("priority") && Integer(entry["priority"]) <= 3

      entry["id"].to_s
    end

    assert_equal expected, Master::Fix::ConstitutionalCheck.priority_constitutional_ids
  end

  def test_unavailable_priority_catalogue_blocks_unclassified_error_findings
    check = Master::Fix::ConstitutionalCheck
    had_ids = check.instance_variable_defined?(:@priority_constitutional_ids)
    old_ids = check.instance_variable_get(:@priority_constitutional_ids)
    had_loaded = check.instance_variable_defined?(:@priority_constitutional_ids_loaded)
    old_loaded = check.instance_variable_get(:@priority_constitutional_ids_loaded)
    check.remove_instance_variable(:@priority_constitutional_ids) if had_ids
    check.remove_instance_variable(:@priority_constitutional_ids_loaded) if had_loaded

    Master.stub(:law_entries, ->(**_options) { raise IOError, "catalogue unavailable" }) do
      findings = [{ severity: :error, law_id: "UNMAPPED_LAW" }]
      refute check.admit_clean?(findings)
    end
  ensure
    if defined?(check) && check
      check.instance_variable_set(:@priority_constitutional_ids, old_ids) if had_ids
      check.remove_instance_variable(:@priority_constitutional_ids) if !had_ids && check.instance_variable_defined?(:@priority_constitutional_ids)
      check.instance_variable_set(:@priority_constitutional_ids_loaded, old_loaded) if had_loaded
      check.remove_instance_variable(:@priority_constitutional_ids_loaded) if !had_loaded && check.instance_variable_defined?(:@priority_constitutional_ids_loaded)
    end
  end

  def test_veto_is_blocking
    findings = [{ severity: :veto, tier: "constitutional" }]
    refute Master::Fix::ConstitutionalCheck.admit_clean?(findings)
  end
end
