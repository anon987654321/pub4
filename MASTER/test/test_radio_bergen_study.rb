# frozen_string_literal: true

require "yaml"
require "minitest/autorun"
require "tmpdir"
require_relative "../../STUDIO/dilla/dilla"

class RadioBergenStudyUnitTest < Minitest::Test
  FAST_AUDIO = ->(path) { path ? { duration_seconds: 180.0 } : nil }.freeze

  def with_fast_audio_analysis
    original = RadioBergenStudy.method(:analyze_audio)
    RadioBergenStudy.define_singleton_method(:analyze_audio, &FAST_AUDIO)
    yield
  ensure
    RadioBergenStudy.define_singleton_method(:analyze_audio, original) if original
  end

  # The invariant is that the study covers the whole manifest, not that the
  # manifest holds a particular number of rows. brgen's catalogue grows, so a
  # literal count here pins RAILS data from MASTER's test directory and fails
  # naming that growth as the regression.
  def test_studies_all_manifest_tracks
    manifest = RadioBergenStudy.load_manifest
    local = Array(manifest["local_mp3"]).length
    youtube = Array(manifest.dig("external_reference", "youtube")).length
    data = with_fast_audio_analysis { RadioBergenStudy.study! }

    assert_operator local, :>, 0, "the manifest must carry local tracks for this to measure anything"
    assert_equal local + youtube, data.dig("meta", "track_count")
    assert_equal local, data.dig("meta", "local_count")
    assert_equal youtube, data.dig("meta", "youtube_count")
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

    assert weights.key?("warm_minor_vamp")
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
