# frozen_string_literal: true

require_relative "dilla_helper"
require_relative "../dilla/lib/groove"

class TestDillaRecordDna < Minitest::Test
  def test_all_review_profiles_have_bounded_controls
    DillaRecordDna.names.each do |name|
      profile = DillaRecordDna.profile(name)
      %w[density negative_space micro_event_odds ghost_density chord_tone_share drum_density texture_jump].each do |key|
        assert profile.fetch(key).to_f.between?(0.0, 1.0), "#{name}: #{key}"
      end
      assert profile.fetch("phrase_bars").to_i.positive?, "#{name}: phrase_bars"
      assert profile.fetch("chord_bars").to_i.positive?, "#{name}: chord_bars"
      assert profile.fetch("texture_change_bars").to_i.positive?, "#{name}: texture_change_bars"
      assert profile.fetch("swing").to_f.between?(50, 60), "#{name}: swing"
    end
  end

  def test_composition_is_seeded_and_keeps_the_supplied_chord_material
    DillaRecordDna.names.each do |name|
      chords = %w[Cm9 Fm9 Bb13 Ebmaj7]
      first = DillaRecordDna.compose(name, chords:, bars: 8, seed: 17)
      again = DillaRecordDna.compose(name, chords:, bars: 8, seed: 17)

      assert_equal first, again, name
      events = first[:tracks].values.flatten
      assert_operator events.length, :>, 20, name
      assert events.all? { |event| event[:note].between?(0, 127) }, name
      assert events.all? { |event| event[:velocity].between?(1, 127) }, name
      assert first[:tracks][:harmony].all? { |event| chords.include?(event[:source_chord]) }, name
    end
  end

  def test_profiles_change_the_realized_shape
    chords = %w[Cm9 Fm9 Bb13 Ebmaj7]
    results = DillaRecordDna.names.to_h do |name|
      [name, DillaRecordDna.compose(name, chords:, bars: 8, seed: 23)]
    end
    signatures = results.values.map do |result|
      result[:tracks].values.flatten.map { |event| [event[:at], event[:duration], event[:note], event[:velocity]] }
    end
    assert_equal DillaRecordDna.names.length, signatures.uniq.length
  end

  def test_midi_export_has_a_standard_midi_header_and_all_tracks
    Dir.mktmpdir do |dir|
      path = File.join(dir, "dna.mid")
      result = DillaRecordDna.write_midi("fantastic_2",
                                         chords: %w[Cm9 Fm9 Bb13 Ebmaj7],
                                         bars: 8, dest: path, seed: 9, bpm: 91)
      bytes = File.binread(path)
      assert_equal "MThd", bytes[0, 4]
      assert_equal 1, bytes.unpack1("@8n")
      assert_equal 5, bytes.unpack1("@10n")
      assert_equal DillaRecordDna::PPQ, bytes.unpack1("@12n")
      assert_equal 5, bytes.scan("MTrk").length
      assert_operator result[:notes], :>, 0
    end
  end
end
