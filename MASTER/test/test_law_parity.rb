# frozen_string_literal: true

require_relative "test_helper"
require "master"
require_relative "../lib/fix/law_parity"

class TestLawParity < Minitest::Test
  def test_all_nine_invariant_laws_declare_both_modalities
    parity = Master::Fix::LawParity.new
    catalogue = Master.load_yaml(Master::Fix::LawParity::LAWS_PATH)
    nodes = Master::FlatLawCatalogue.entries(catalogue).select { |entry| entry["node"] }

    assert_equal 9, nodes.size
    assert nodes.all? { |entry| entry["mechanical"].to_s.strip != "" }
    assert nodes.all? { |entry| entry["semantic"].to_s.strip != "" }
    assert nodes.all? { |entry| entry["enforcement"] == "declared" }
    assert_empty parity.call, parity.report
    assert_match(/declarations complete/, parity.report)
  end

  def test_parity_does_not_claim_that_declared_detectors_have_executed
    report = Master::Fix::LawParity.new.report

    assert_match(/execution evidence measured separately/, report)
    refute_match(/runtime enforcement passed|all detectors passed/i, report)
  end

  def test_missing_modality_declaration_invalidates_the_constitution
    catalogue = Master.load_yaml(Master::Fix::LawParity::LAWS_PATH)
    catalogue.fetch("ROBUSTNESS").delete("mechanical")

    error = assert_raises(Master::FlatLawCatalogue::Invalid) do
      Master::FlatLawCatalogue.validate!(catalogue)
    end
    assert_match(/ROBUSTNESS must declare mechanical enforcement/, error.message)
  end

  def test_deterministic_coverage_must_name_a_detector
    catalogue = Master.load_yaml(Master::Fix::LawParity::LAWS_PATH)
    catalogue.fetch("TRUTHFUL_STATUS")["detector_ids"] = []

    error = assert_raises(Master::FlatLawCatalogue::Invalid) do
      Master::FlatLawCatalogue.validate!(catalogue)
    end
    assert_match(/deterministic coverage must name detector_ids/, error.message)
  end

  def test_numeric_priority_is_rejected_from_the_normative_catalogue
    catalogue = Master.load_yaml(Master::Fix::LawParity::LAWS_PATH)
    catalogue.fetch("ROBUSTNESS")["priority"] = 1

    error = assert_raises(Master::FlatLawCatalogue::Invalid) do
      Master::FlatLawCatalogue.validate!(catalogue)
    end
    assert_match(/retired ranking field/, error.message)
  end

  def test_empty_catalogue_is_not_reported_as_clean
    error = assert_raises(Master::FlatLawCatalogue::Invalid) do
      Master::FlatLawCatalogue.validate!({})
    end
    assert_match(/no flat laws/, error.message)
  end

  def test_enforcement_overlay_has_been_retired
    refute File.exist?(File.join(Master::ROOT, "data", "law_enforcement.yml"))
  end
end
