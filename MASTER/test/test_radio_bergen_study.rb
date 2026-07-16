# frozen_string_literal: true

require "yaml"
require "minitest/autorun"
require_relative "../tools/dilla/dilla"

class RadioBergenStudyUnitTest < Minitest::Test
  def test_studies_all_manifest_tracks
    data = RadioBergenStudy.study!

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
    weights = RadioBergenStudy.study!["stream_rotation_weights"]

    assert weights.key?("erykah_minor")
    assert weights.key?("quartal_west_coast")
    assert weights.key?("neo_soul_pocket")
  end

  def test_yaml_output_uses_string_keys
    path = RadioBergenStudy.write!
    data = YAML.safe_load(File.read(path))

    assert data["playlist_tracks"].first.key?("title")
    refute data["playlist_tracks"].first.key?(:title)
  end
end