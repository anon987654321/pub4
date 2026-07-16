# frozen_string_literal: true

require "test_helper"
require_relative "../../../../MASTER/tools/audio/radio_bergen_study"

class RadioBergenStudyTest < ActiveSupport::TestCase
  test "studies all manifest tracks" do
    data = RadioBergenStudy.study!

    assert_operator data.dig("meta", "track_count").to_i, :>=, 25
    assert_equal 9, data.dig("meta", "local_count")
    assert_operator data.dig("meta", "youtube_count").to_i, :>=, 18
  end

  test "maps j dilla references to dilla dna" do
    rows = RadioBergenStudy.catalog_rows
    dilla = rows.find { |r| r[:title] == "Microphone Master" }
    aff = RadioBergenStudy.affinity_for(dilla[:artist])

    assert_equal "dilla", aff[:producer]
    assert_equal "maj7_minor_cycle", aff[:dilla_track]
  end

  test "stream rotation weights favor bergen local and flylo slum dilla mix" do
    data = RadioBergenStudy.study!
    weights = data["stream_rotation_weights"]

    assert weights.key?("erykah_minor")
    assert weights.key?("quartal_west_coast")
    assert weights.key?("neo_soul_pocket")
  end

  test "brgen manifest loader exposes sonic learnings when file present" do
    skip "sonic learnings not checked out" unless Brgen::RadioBergenManifest.sonic_learnings_path

    weights = Brgen::RadioBergenManifest.stream_rotation_weights

    assert_operator weights.size, :>=, 5
  end
end