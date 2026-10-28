# frozen_string_literal: true

require "minitest/autorun"
require "tempfile"
require_relative "../postpro/lib/quality_analyzer"
require_relative "../postpro/lib/correction_proposer"
require_relative "../replicate/replay_manifest"

class StudioQualityAndReplayTest < Minitest::Test
  def test_quality_report_is_bounded_and_truthful
    report = Postpro::QualityAnalyzer.report(luminance: [0.0, 0.2, 0.5, 0.8, 1.0])
    assert_equal 5, report[:sample_count]
    assert_equal 20.0, report.dig(:exposure, :clipped_highlights_pct)
    assert_includes report[:not_assessed], :composition
    refute report.dig(:colour, :available)
  end

  def test_empty_luminance_is_rejected
    assert_raises(ArgumentError) { Postpro::QualityAnalyzer.report(luminance: []) }
  end

  def test_correction_proposals_are_limited_and_disclose_scope
    report = Postpro::QualityAnalyzer.report(luminance: [0.1, 0.11, 0.12, 0.13])
    proposal = Postpro::CorrectionProposer.propose(report, constraints: { max_exposure_stops: 0.5 })
    assert_operator proposal[:exposure_bias_stops].abs, :<=, 0.5
    assert proposal[:requires_operator_review]
    assert_includes proposal[:not_addressed], :focus_quality
  end

  def test_replay_manifest_hashes_output_and_prompt_without_storing_prompt
    Tempfile.create("studio-output") do |file|
      file.write("rendered bytes")
      file.flush
      manifest = Studio::ReplayManifest.build(
        output_path: file.path, prompt: "private prompt",
        model: { id: "model-x", version: "1", hash: "abc" },
        style: { style_id: "blue-hour", version: "1.0.0", lineage: {}, influence: {} },
        params: { seed: 7 }
      )
      refute manifest.key?(:prompt)
      assert Studio::ReplayManifest.verify_output!(manifest, output_path: file.path)
      assert_equal 64, Studio::ReplayManifest.digest(manifest).length
    end
  end

  def test_replay_manifest_detects_changed_output
    Tempfile.create("studio-output") do |file|
      file.write("before")
      file.flush
      manifest = Studio::ReplayManifest.build(
        output_path: file.path, prompt: "brief", model: { id: "m" },
        style: { style_id: "s", version: "1.0.0" }, params: {}
      )
      file.rewind
      file.truncate(0)
      file.write("after")
      file.flush
      assert_raises(ArgumentError) { Studio::ReplayManifest.verify_output!(manifest, output_path: file.path) }
    end
  end
end
