# frozen_string_literal: true

require_relative "test_helper"
require "master"
require_relative "../lib/fix/constitutional_check"

class TestConstitutionalCheck < Minitest::Test
  CHECK = Master::Fix::ConstitutionalCheck

  def reset_cache
    CHECK.remove_instance_variable(:@constitutional_law_ids) if CHECK.instance_variable_defined?(:@constitutional_law_ids)
    CHECK.remove_instance_variable(:@constitutional_law_ids_loaded) if CHECK.instance_variable_defined?(:@constitutional_law_ids_loaded)
  end

  def test_admits_clean_when_no_findings
    assert CHECK.admit_clean?([])
  end

  def test_blocks_error_for_a_constitutional_node
    findings = [{ severity: :error, law_id: "ROBUSTNESS", message: "x" }]
    refute CHECK.admit_clean?(findings)
    assert_equal 1, CHECK.residual_errors(findings).size
  end

  def test_blocks_any_explicit_constitutional_error
    findings = [{ severity: :error, tier: "constitutional", law_id: "ANY_LAW", message: "x" }]
    refute CHECK.admit_clean?(findings)
  end

  def test_allows_warning_without_constitutional_classification
    assert CHECK.admit_clean?([{ severity: :warning, id: "style_nit" }])
  end

  def test_constitutional_nodes_come_from_the_ordered_law_catalogue
    expected = Master::FlatLawCatalogue.entries(Master.load_yaml(Master::Fix::LawParity::LAWS_PATH))
      .filter_map { |entry| entry["id"].to_s if entry["node"] }

    assert_equal 9, expected.size
    assert_equal expected, CHECK.constitutional_law_ids
  end

  def test_unavailable_catalogue_blocks_unclassified_error_findings
    reset_cache
    Master.stub(:law_entries, ->(**_options) { raise IOError, "catalogue unavailable" }) do
      refute CHECK.admit_clean?([{ severity: :error, law_id: "UNMAPPED_LAW" }])
    end
  ensure
    reset_cache
  end

  def test_veto_is_blocking
    refute CHECK.admit_clean?([{ severity: :veto, tier: "constitutional" }])
  end
end
