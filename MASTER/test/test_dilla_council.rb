# frozen_string_literal: true

require_relative "test_helper"
require "review/council/critique"
require "review/council/personas"
require "review/council/quality_framework"
require "voice/mix_metrics"

class TestDillaCouncil < Minitest::Test
  def test_dilla_critique_mode_is_registered
    modes = Master::Review::Council::Critique::MODES
    assert modes.key?(:dilla)
    assert modes.key?(:sound)
    dilla = modes[:dilla]
    assert_equal "dilla_critique", dilla[:preset_key]
    assert dilla[:include_mix_metrics]
    assert_operator dilla[:max_bytes], :>=, 400_000
    assert_match(/cherry-pick/i, dilla[:ideation_prompt])
    assert_includes dilla[:files], "../STUDIO/dilla/dilla.rb"
    assert_includes dilla[:files], "../STUDIO/dilla/data/dilla.json"
    assert_includes dilla[:files], "../STUDIO/dilla/data/showcase.json"
    assert_includes dilla[:files], "../STUDIO/dilla/data/music_theory.json"
    assert_includes dilla[:files], "../STUDIO/dilla/data/recovered_music.json"
    refute dilla[:files].any? { |path| path.include?("../STUDIO/dilla/lib/dilla/") }
  end

  def test_dilla_preset_sources_resolve_from_master_root
    data = Master.load_yaml(Master::COUNCIL_PATH)
    files = data.dig("presets", "dilla_critique", "files")

    refute_empty files
    files.each do |relative|
      path = File.expand_path(relative, Master::ROOT)
      assert File.file?(path), "missing Dilla council source: " + relative + " -> " + path
    end
  end

  def test_dilla_panel_personas_exist_in_council_yaml
    names = Master::Review::Council::Personas.load.map(&:name)
    [
      "Electronic Music Producer", "Sound Engineer", "Label Executive", "Graphic Designer", "Web Designer", "Sound Designer", "Organ Composer"
    ].each do |name|
      assert_includes names, name
    end
  end

  def test_quality_framework_maps_new_sound_personas
    assert_equal :sound, Master::Review::Council::QualityFramework.domain_for("Sound Engineer")
    assert_equal :sound, Master::Review::Council::QualityFramework.domain_for("Organ Composer")
    brief = Master::Review::Council::QualityFramework.brief(:sound)
    assert_match(/cherry-pick/i, brief)
  end

  def test_mix_metrics_brief_handles_missing_file
    text = Master::Voice::MixMetrics.brief("/no/such/demo.wav")
    assert_match(/missing|error/i, text)
  end

  def test_mix_metrics_from_demo_when_present
    demo = File.join(Master::ROOT, "..", "STUDIO/dilla/out/loop.wav")
    skip "demo.wav missing" unless File.file?(demo)
    skip "ffmpeg not available" unless system("which ffmpeg > /dev/null 2>&1")
    m = Master::Voice::MixMetrics.from_path(demo)
    refute m[:error]
    assert m[:peak_db]
    assert m[:air_db]
  end
end
