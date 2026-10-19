# frozen_string_literal: true

require "minitest/autorun"
require "json"

class RecoveredMusicTest < Minitest::Test
  DILLA_ROOT = File.expand_path("../dilla", __dir__)
  PATH = File.join(DILLA_ROOT, "data", "recovered_music.json")

  def catalog
    @catalog ||= JSON.parse(File.read(PATH))
  end

  def test_archive_provenance_and_scope_are_explicit
    meta = catalog.fetch("meta")

    assert_equal "dilla.recovered_music.v1", meta.fetch("schema")
    assert_equal "anon987654321/pub3:multimedia/dilla/dilla_data.json", meta.fetch("recovered_from")
    assert_includes meta.fetch("purpose"), "without presenting them as verified transcriptions"
    assert_includes meta.fetch("rules").join(" "), "never added to the default stream rotation"
  end

  def test_named_legacy_progressions_retain_playing_and_source_metadata
    progressions = catalog.fetch("documented_progressions")

    assert_equal 42, progressions.length
    progressions.each do |name, row|
      assert_match(/\Alegacy_/, name)
      assert_operator row.fetch("chords").length, :>=, 3
      assert_operator row.fetch("bpm"), :>=, 30
      assert_operator row.fetch("bpm"), :<=, 300
      assert row.fetch("source").include?("dilla_data.json"), "#{name} has no source"
      assert_includes row.fetch("source_note"), "not verified transcriptions"
    end
  end

  def test_grouped_harmony_drum_research_and_sample_leads_survive
    groups = catalog.fetch("legacy_progression_groups")
    assert_equal 3, groups.length
    assert_equal 42, groups.values.sum(&:length)

    drums = catalog.fetch("drums")
    %w[hip_hop_patterns jazz_patterns reggae_patterns swing_theory synthesis_parameters techno_house_patterns].each do |name|
      assert drums.key?(name), "missing recovered drum research section #{name}"
    end

    studies = catalog.fetch("sample_studies")
    assert_equal 5, studies.length
    assert studies.all? { |row| %w[candidate_unverified research_lead].include?(row.fetch("status")) }
  end
end
