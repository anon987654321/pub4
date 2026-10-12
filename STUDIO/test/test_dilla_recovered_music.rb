# frozen_string_literal: true

require_relative "dilla_helper"

class TestDillaRecoveredMusic < Minitest::Test
  def test_legacy_progressions_are_available_without_entering_default_rotation
    legacy = DillaLofiMachine::HARMONY_PROFILES.keys.grep(/\Alegacy_/)
    assert_equal 42, legacy.length
    assert legacy.all? { |key| DillaLofiMachine::HARMONY_PROFILES.fetch(key)[:source_note].to_s.include?("not verified") }
    assert_empty legacy & DillaLofiMachine::STREAM_ROTATION.map(&:to_sym)
  end

  def test_recovered_drum_patterns_are_addressable_but_not_the_default
    %i[legacy_dilla_classic legacy_flylo_broken legacy_madlib_dusty legacy_boom_bap_classic].each do |name|
      assert DillaLofiMachine::DRUM_PRESETS.key?(name), "missing recovered drum pattern #{name}"
      preset = DillaLofiMachine::DRUM_PRESETS.fetch(name)
      assert preset.fetch(:kicks).all? { |step| (0..15).cover?(step) }
      assert preset.fetch(:snares).all? { |step| (0..15).cover?(step) }
    end
    assert_equal :dilla_slight, DillaLofiMachine::DEFAULT_DRUM_PRESET
  end

  def test_missing_legacy_extension_templates_are_preserved
    expected = {
      "maj11" => [0, 4, 7, 11, 14, 17],
      "11" => [0, 4, 7, 10, 14, 17],
      "9b5" => [0, 4, 6, 10, 14],
      "9#5" => [0, 4, 8, 10, 14],
      "6add9" => [0, 4, 7, 9, 14],
      "m7b13" => [0, 3, 7, 10, 20]
    }
    expected.each do |quality, intervals|
      assert_equal intervals, DillaLofiMachine::CHORD_TEMPLATES.fetch(quality), quality
      assert_includes DillaLofiMachine::CHORD_SUFFIXES, quality
    end
  end

  def test_every_recovered_progression_chord_resolves
    symbols = DillaLofiMachine::HARMONY_PROFILES
      .select { |key, _profile| key.to_s.start_with?("legacy_") }
      .values.flat_map { |profile| profile.fetch(:chords) }
      .uniq
    unresolved = symbols.reject { |symbol| DillaLofiMachine.chord_from_symbol(symbol) }
    assert_empty unresolved, "legacy chords were silently dropped: #{unresolved.inspect}"
  end

  def test_recovered_catalog_marks_sample_links_as_unverified
    catalog_path = File.expand_path("../dilla/data/recovered_music.json", __dir__)
    data = JSON.parse(File.read(catalog_path))
    candidates = data.fetch("sample_studies")
    assert_equal 5, candidates.length
    assert candidates.all? { |row| %w[candidate_unverified research_lead].include?(row.fetch("status")) }
  end
end
