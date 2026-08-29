# frozen_string_literal: true

require_relative "dilla_helper"

# Two CHORD_TEMPLATES tables live in this engine -- chord_theory.rb's and
# DillaLofiMachine's -- with different coverage and, until recently, one
# outright disagreement (7alt). Which chord a render got depended on which of
# two code paths it reached. These pin the resolution order and the voicing
# arithmetic that made altered chords sound blunt.
class TestChordTheory < Minitest::Test
  def test_every_template_is_rooted_at_zero
    CHORD_TEMPLATES.each do |quality, intervals|
      assert_equal 0, intervals.first, "#{quality} does not start on its root"
      assert_operator intervals.size, :>=, 3, "#{quality} is not a chord"
    end
  end

  # The disagreement that used to exist. 7alt means the fifth AND the ninth are
  # altered; with a perfect fifth at 7 it was a 7b9 wearing an altered
  # dominant's name.
  def test_the_two_template_tables_agree_where_they_overlap
    other = DillaLofiMachine::CHORD_TEMPLATES
    shared = CHORD_TEMPLATES.keys & other.keys
    refute_empty shared

    disagreements = shared.reject { |q| CHORD_TEMPLATES[q] == other[q] }
    assert_empty disagreements,
                 "a render's chord depends on which table it reached: #{disagreements.inspect}"
  end

  # A quality this table lacks must fall through rather than raise a bare
  # KeyError from inside a render.
  def test_lookup_falls_through_to_the_other_table
    refute CHORD_TEMPLATES.key?("m7b5"), "this test is about a quality only the other table has"
    assert_equal DillaLofiMachine::CHORD_TEMPLATES["m7b5"], send(:chord_template_for, "m7b5")
  end

  def test_an_unknown_quality_lands_on_maj9_rather_than_raising
    assert_equal CHORD_TEMPLATES.fetch("maj9"), send(:chord_template_for, "not_a_chord")
  end

  # Ninths written in simple form voice as a second against the root -- a
  # cluster, audibly worse than the extension being absent. Any interval
  # smaller than one already seen is an extension and belongs an octave up.
  def test_extensions_are_raised_into_the_octave_they_belong_in
    assert_equal [0, 3, 7, 10, 14], send(:voice_extensions, CHORD_TEMPLATES["m9"])
    assert_equal [0, 4, 7, 11, 14], send(:voice_extensions, CHORD_TEMPLATES["maj9"])
    assert_equal [0, 4, 7, 10, 18], send(:voice_extensions, CHORD_TEMPLATES["7#11"])
  end

  def test_voicing_ascends_after_extensions_are_raised
    CHORD_TEMPLATES.each do |quality, intervals|
      voiced = send(:voice_extensions, intervals)
      assert_equal voiced.sort, voiced, "#{quality} still voices an extension as a cluster"
    end
  end

  def test_a_chord_is_built_at_the_requested_pitch_and_width
    hz = send(:chord_from_root, 220.0, "maj", voices: 6)

    assert_equal 6, hz.size
    assert_equal hz.sort, hz, "chord tones come back ascending"
    assert_in_delta 220.0, hz.first, 0.01
    assert_in_delta 277.18, hz[1], 0.01, "major third"
    assert_in_delta 329.63, hz[2], 0.01, "perfect fifth"
  end

  # `voices` is a ceiling, not a promise: the padding rule doubles thirds and
  # sevenths rather than stacking roots, so a quality can come up short. What
  # must hold is that it never overshoots and never narrows as it is widened.
  def test_the_voice_count_is_a_ceiling_that_widens_monotonically
    sizes = [3, 4, 5, 6].map do |voices|
      hz = send(:chord_from_root, 220.0, "m9", voices:)
      assert_operator hz.size, :<=, voices, "asked for #{voices} voices and got more"
      assert_operator hz.size, :>=, 3, "a chord narrower than a triad is not a chord"
      hz.size
    end

    assert_equal sizes.sort, sizes, "widening the voicing narrowed the chord"
  end

  # Six, not five: 13 and maj13 carry six chord tones and at five the topmost
  # after sorting was dropped, which is the extension that names the chord.
  def test_six_tone_qualities_keep_the_note_that_names_them
    intervals = send(:voice_extensions, send(:chord_template_for, "13"))
    skip "this build's tables carry no 13" if intervals.size < 6

    hz = send(:chord_from_root, 110.0, "13", voices: 6)
    top = 110.0 * (2**(intervals.max / 12.0))
    assert_operator hz.max, :>=, top - 0.5, "the thirteenth was trimmed off"
  end

  def test_scale_degree_qualities_all_resolve_to_a_template
    SCALE_DEGREE_QUALITY.each do |mode, degrees|
      degrees.each do |degree, quality|
        refute_nil send(:chord_template_for, quality),
                   "#{mode} degree #{degree} names a quality no table carries"
      end
    end
  end

  def test_the_functional_walk_stays_inside_the_scale
    DEGREE_TRANSITIONS.each do |from, targets|
      assert_includes 1..7, from
      targets.each do |to, weight|
        assert_includes 1..7, to, "degree #{from} walks to #{to}, which is not a scale degree"
        assert_operator weight, :>, 0, "a zero weight is an edge that is never taken"
      end
    end
  end

  def test_the_dominant_resolves_home_more_often_than_it_deceives
    dominant = DEGREE_TRANSITIONS.fetch(5)
    assert_operator dominant.fetch(1), :>, dominant.fetch(6),
                    "V->I must outweigh the deceptive V->vi or the harmony never settles"
  end

  def test_weighted_pick_follows_the_weights
    weights = { a: 1, b: 99 }
    counts = Hash.new(0)
    rng = Random.new(1234)
    2000.times { counts[send(:weighted_pick, rng, weights)] += 1 }

    assert_operator counts[:b], :>, counts[:a] * 10
    assert_equal counts.values.sum, 2000
  end

  def test_weighted_pick_never_leaves_the_key_set
    rng = Random.new(1)
    weights = { 1 => 3, 4 => 1 }
    200.times { assert_includes weights.keys, send(:weighted_pick, rng, weights) }
  end

  def test_both_scales_are_seven_note_and_ascend_within_an_octave
    SCALE_SEMITONES.each do |mode, degrees|
      assert_equal 7, degrees.size, "#{mode} is not a seven-note scale"
      assert_equal degrees.sort, degrees
      assert_operator degrees.last, :<, 12
      assert_equal 0, degrees.first
    end
  end

  # Correlating a measured chroma against 24 rotations is only meaningful if
  # both profiles cover all twelve pitch classes.
  def test_key_profiles_cover_twelve_pitch_classes
    assert_equal 12, KRUMHANSL_MAJOR.size
    assert_equal 12, KRUMHANSL_MINOR.size
    [KRUMHANSL_MAJOR, KRUMHANSL_MINOR].each do |profile|
      assert_equal 0, profile.index(profile.max), "the tonic is not the strongest degree"
    end
  end

  # Layering a pad in the wrong key is worse than layering nothing, so the
  # guard is on unless explicitly disabled, and its thresholds are ordered.
  def test_the_harmonic_guard_thresholds_are_ordered
    assert_operator HARMONIC_MUTE_MIN, :<, HARMONIC_GUARD_MIN,
                    "the mute floor must sit under the guard floor or one of them is unreachable"
    assert_operator HARMONIC_MUTE_MIN, :>, 0.0
    assert_operator HARMONIC_GUARD_MIN, :<, 1.0
  end
end
