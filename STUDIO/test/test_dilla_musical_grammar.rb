# frozen_string_literal: true

require_relative "dilla_helper"
require_relative "../dilla/lib/livesets"

class TestDillaMusicalGrammar < Minitest::Test
  def with_env(pairs)
    saved = pairs.keys.to_h { |key| [key, ENV.fetch(key, nil)] }
    pairs.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def test_curated_progressions_are_original_and_parseable
    refute_empty DillaMusicalGrammar::CURATED_PROGRESSIONS

    DillaMusicalGrammar::CURATED_PROGRESSIONS.each do |name, cells|
      assert_equal 8, cells.length, name
      cells.each do |degree, quality|
        assert degree.is_a?(Integer), name
        assert DillaImprovisation::QUALITIES.key?(quality), "#{name}: #{quality}"
        symbol = "#{DillaImprovisation::PITCH_NAMES[degree % 12]}#{quality}"
        assert Livesets.parse_chord(symbol), "#{name}: #{symbol} does not resolve"
      end
    end

    names = DillaMusicalGrammar::CURATED_PROGRESSIONS.keys.map(&:to_s)
    refute names.any? { |name| name.match?(/documented|reference|verified/) }
  end

  def test_motif_target_is_bounded_and_harmonic
    scale = [0, 2, 3, 5, 7, 9, 10]
    chord = [0, 3, 7, 10]
    previous = 67
    notes = 24.times.map do |step|
      note = DillaMusicalGrammar.motif_target(
        scale_pcs: scale,
        chord_pcs: chord,
        range: 60..84,
        previous: previous,
        step:,
        tension: step % 8 / 7.0
      )
      previous = note
      note
    end

    assert notes.all? { |note| (60..84).cover?(note) }
    assert notes.all? { |note| scale.include?(note % 12) }
    assert_operator notes.uniq.length, :>=, 5
  end

  def test_fugue_subject_and_tonal_answer_have_equal_shape
    scale = [0, 2, 3, 5, 7, 9, 10]
    chord = [0, 3, 7, 10]
    subject = DillaMusicalGrammar.fugue_subject(scale, chord, range: 64..88)
    answer = DillaMusicalGrammar.tonal_answer(subject, scale_pcs: scale, range: 52..76)

    assert_equal 8, subject.length
    assert_equal subject.length, answer.length
    assert subject.all? { |note| (64..88).cover?(note) }
    assert answer.all? { |note| (52..76).cover?(note) }
    assert answer.all? { |note| scale.include?(note % 12) }
  end

  def test_showcase_can_select_a_curated_harmony_instead_of_the_markov_walk
    with_env(
      "DILLA_CURATED_HARMONY" => "1",
      "DILLA_FUGUE" => "1",
      "DILLA_SHOWCASE" => "0",
      "LIVE_REFERENCE" => nil
    ) do
      improviser = LiveSynth::Improviser.new(rng: Random.new(9), family: "prophet", drums: false)
      assert_nil improviser.instance_variable_get(:@reference)
      refute_nil improviser.instance_variable_get(:@curated_progression)
      assert_equal 8, improviser.instance_variable_get(:@curated_progression).length
      assert improviser.instance_variable_get(:@fugue_enabled)
    end
  end

  def test_fugue_builds_two_independent_eight_note_voices
    with_env(
      "DILLA_SHOWCASE" => "0",
      "DILLA_FUGUE" => "1",
      "LIVE_REFERENCE" => nil
    ) do
      improviser = LiveSynth::Improviser.new(rng: Random.new(14), family: "prophet", drums: false)
      improviser.instance_variable_set(:@lead_scale_pcs, [0, 2, 3, 5, 7, 9, 10])
      improviser.instance_variable_set(:@lead_chord_pcs, [0, 3, 7, 10])
      improviser.instance_variable_set(:@lead, "poly_lead")
      improviser.instance_variable_set(:@next_at, 0.0)

      captured = []
      improviser.define_singleton_method(:stage_midi_events!) do |stage, events, **kwargs|
        captured << [events, kwargs]
      end

      improviser.send(:fugue_phrase!, nil, 8.0)

      assert_equal 2, captured.length
      assert_equal [8, 8], captured.map { |events, _| events.length }
      assert captured.all? { |events, _| events.all? { |event| event.midi.between?(64, 88) } }
      assert_operator captured.last.first.first.at, :>, captured.first.first.first.at
    end
  end

  def test_soul_pocket_declares_all_four_drum_roles
    preset = DillaLofiMachine::DRUM_PRESETS.fetch(:dilla_soul_pocket)

    assert_equal [0, 6, 10, 15], preset.fetch(:kicks)
    assert_equal [4, 12], preset.fetch(:snares)
    refute_empty preset.fetch(:claps)
    refute_empty preset.fetch(:perc)
  end

  def test_live_config_uses_the_soul_pocket
    assert_equal "dilla_soul_pocket",
                 LiveSynth.config.fetch("improvise").fetch("drum_preset")
  end

  def test_curated_bass_can_see_the_next_harmonic_root
    with_env(
      "DILLA_SHOWCASE" => "0",
      "DILLA_FUGUE" => "1",
      "LIVE_REFERENCE" => nil
    ) do
      improviser = LiveSynth::Improviser.new(rng: Random.new(22), family: "prophet", drums: false)
      progression = improviser.instance_variable_get(:@curated_progression)
      assert_equal 8, progression.length
      key = improviser.instance_variable_get(:@key)
      current_index = improviser.instance_variable_get(:@curated_index)
      next_degree = progression.fetch(current_index % progression.length).first
      assert_equal (key + next_degree) % 12, improviser.send(:next_root_pc)
    end
  end

  def test_kit_realizes_clap_and_percussion_layers
    config = LiveSynth.config.fetch("improvise")
    beat = 60.0 / 92.0
    kit = LiveSynth::Kit.new(config, beat:, rng: Random.new(19), preset: :dilla_soul_pocket)
    kit.write!(0.0, beat * 4.0)

    refute_empty kit.instance_variable_get(:@claps)
    refute_empty kit.instance_variable_get(:@percs)

    left = Array.new(1024, 0.0)
    right = Array.new(1024, 0.0)
    kick = kit.render!(left, right, 0.0, 1024.0 / beat)
    assert kick.all?(&:finite?)
    assert left.all?(&:finite?)
    assert right.all?(&:finite?)
  end
end
