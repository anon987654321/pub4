# frozen_string_literal: true

require "minitest/autorun"
require "tempfile"
require "json"
require_relative "../postpro/lib/quality_analyzer"
require_relative "../postpro/lib/correction_proposer"
require_relative "../replicate/replay_manifest"

class StudioFakePixelImage
  attr_reader :width, :height, :bands

  def initialize(bytes, width: 2, height: 2, bands: 3)
    @bytes, @width, @height, @bands = bytes, width, height, bands
  end

  def thumbnail_image(_width, height:, size:)
    raise ArgumentError unless height.positive? && size == :down
    self
  end

  def colourspace(_space) = self
  def cast(_format) = self
  def write_to_memory = @bytes
end

class StudioQualityAndReplayTest < Minitest::Test
  def test_quality_report_is_bounded_and_truthful
    report = Postpro::QualityAnalyzer.report(luminance: [0.0, 0.2, 0.5, 0.8, 1.0])
    assert_equal 5, report[:sample_count]
    assert_equal 20.0, report.dig(:exposure, :clipped_highlights_pct)
    assert_includes report[:not_assessed], :composition
    refute report.dig(:colour, :available)
  end

  def test_image_adapter_downsamples_rgb_pixels_and_returns_dimensions
    pixels = [0, 0, 0, 64, 64, 64, 128, 128, 128, 255, 255, 255].pack("C*")
    image = StudioFakePixelImage.new(pixels, width: 3200, height: 2400)
    report = Postpro::QualityAnalyzer.report_image(image)

    assert_equal [3200, 2400], report[:dimensions]
    assert_equal [2, 2], report[:sample_dimensions]
    assert_equal 4, report[:sample_count]
    assert_equal "uniform thumbnail; encoded-sRGB luminance approximation", report[:sampling]
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

  def test_high_variance_detail_is_not_misclassified_as_missing_detail
    report = Postpro::QualityAnalyzer.report(luminance: [0.0, 0.24, 0.76, 1.0])
    assert_operator report.dig(:tonal, :shadow_detail_ratio), :>, 0.9
    assert_operator report.dig(:tonal, :highlight_detail_ratio), :>, 0.9

    proposal = Postpro::CorrectionProposer.propose(report)
    refute proposal.fetch(:tone_curve, {}).key?(:shadow_lift)
    refute proposal.fetch(:tone_curve, {}).key?(:highlight_rolloff)
  end

  def test_missing_shadow_and_highlight_samples_do_not_trigger_tone_curve_proposals
    report = Postpro::QualityAnalyzer.report(luminance: [0.5, 0.5, 0.5, 0.5])
    assert_nil report.dig(:tonal, :shadow_detail_ratio)
    assert_nil report.dig(:tonal, :highlight_detail_ratio)

    proposal = Postpro::CorrectionProposer.propose(report)
    refute proposal.key?(:tone_curve)
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
      persisted = JSON.parse(JSON.generate(manifest))
      assert Studio::ReplayManifest.verify_output!(persisted, output_path: file.path)
      assert_equal 64, Studio::ReplayManifest.digest(manifest).length
    end
  end

  def test_replayability_requires_the_selected_modality_to_match_the_declared_version
    manifest = { "style_id" => "blue_hour", "style_version" => "1.0.0", "modality" => "image" }
    registry = {
      "styles" => {
        "blue_hour" => {
          "versions" => {
            "1.0.0" => { "modalities" => {
              "image" => { "version" => "1.0.0", "temporal_variation" => "none" },
              "prompt" => { "version" => "1.0.0", "temporal_variation" => "none" }
            } }
          }
        }
      }
    }
    assert Studio::ReplayManifest.replayable?(manifest, registry)

    registry["styles"]["blue_hour"]["versions"]["1.0.0"]["modalities"]["image"]["version"] = "2.0.0"
    refute Studio::ReplayManifest.replayable?(manifest, registry)
  end

  def test_temporal_replay_requires_the_registry_schedule_hash_in_the_manifest
    schedule_hash = "a" * 64
    registry = {
      "styles" => {
        "blue_hour" => {
          "versions" => {
            "1.0.0" => { "modalities" => {
              "image" => {
                "version" => "1.0.0",
                "temporal_variation" => { "schedule_hash" => schedule_hash }
              }
            } }
          }
        }
      }
    }
    manifest = {
      "style_id" => "blue_hour", "style_version" => "1.0.0", "modality" => "image",
      "temporal_schedule_hash" => schedule_hash
    }
    assert Studio::ReplayManifest.replayable?(manifest, registry)

    manifest["temporal_schedule_hash"] = "b" * 64
    refute Studio::ReplayManifest.replayable?(manifest, registry)
    manifest.delete("temporal_schedule_hash")
    refute Studio::ReplayManifest.replayable?(manifest, registry)
  end

  def test_manifest_carries_a_declared_temporal_schedule_hash
    Tempfile.create("studio-temporal-output") do |file|
      file.write("frame")
      file.flush
      schedule_hash = "c" * 64
      manifest = Studio::ReplayManifest.build(
        output_path: file.path, prompt: "repeated style", model: { id: "model-x" },
        style: { style_id: "blue_hour", version: "1.0.0", modality: "image",
                 temporal_variation: { schedule_hash: schedule_hash } },
        params: {}
      )
      assert_equal schedule_hash, manifest.fetch(:temporal_schedule_hash)
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
