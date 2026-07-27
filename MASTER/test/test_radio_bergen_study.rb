# frozen_string_literal: true

require "yaml"
require "minitest/autorun"
require "tmpdir"
require_relative "../../studio/dilla/dilla"

class RadioBergenStudyUnitTest < Minitest::Test
  FAST_AUDIO = ->(path) { path ? { duration_seconds: 180.0 } : nil }.freeze

  def with_fast_audio_analysis
    original = RadioBergenStudy.method(:analyze_audio)
    RadioBergenStudy.define_singleton_method(:analyze_audio, &FAST_AUDIO)
    yield
  ensure
    RadioBergenStudy.define_singleton_method(:analyze_audio, original) if original
  end

  def test_studies_all_manifest_tracks
    data = with_fast_audio_analysis { RadioBergenStudy.study! }

    assert_operator data.dig("meta", "track_count").to_i, :>=, 25
    assert_equal 9, data.dig("meta", "local_count")
    assert_operator data.dig("meta", "youtube_count").to_i, :>=, 18
  end

  def test_maps_j_dilla_to_dilla_dna
    rows = RadioBergenStudy.catalog_rows
    dilla = rows.find { |r| r[:title] == "Microphone Master" }
    aff = RadioBergenStudy.affinity_for(dilla[:artist])

    assert_equal "dilla", aff[:producer]
    assert_equal "maj7_minor_cycle", aff[:dilla_track]
  end

  def test_stream_weights_cover_bergen_and_beat_references
    weights = with_fast_audio_analysis { RadioBergenStudy.study! }["stream_rotation_weights"]

    assert weights.key?("erykah_minor")
    assert weights.key?("quartal_west_coast")
    assert weights.key?("neo_soul_pocket")
  end

  def test_yaml_output_uses_string_keys
    Dir.mktmpdir("radio-bergen-study") do |dir|
      path = with_fast_audio_analysis { RadioBergenStudy.write!(path: File.join(dir, "sonic.yml")) }
      data = YAML.safe_load(File.read(path))

      assert data["playlist_tracks"].first.key?("title")
      refute data["playlist_tracks"].first.key?(:title)
    end
  end
end
