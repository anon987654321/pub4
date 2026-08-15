# frozen_string_literal: true

require_relative "helper"

# The pocket is this table. Every role that falls through SWING_ROLE_SCALE gets
# 1.0 -- the hi-hat's lean -- which is how the four busiest melodic roles came
# to be swung harder than the bass and the pad, and how a bare `:kick` role at
# three call sites swung at 1.0 while `:kick_anchor` sat at 0. Both are the same
# drum. A missing key here is inaudible as a bug and audible as a sequencer.
class TestGrooveTiming < Minitest::Test
  DRUM_ROLES = %i[kick kick_anchor kick_sync snare clap hat hat_down hat_up open ghost perc].freeze
  SUSTAINED_ROLES = %i[bass pad ep warm texture native].freeze
  LEAD_ROLES = %i[lead xlead scale_lead creative_lead].freeze

  def offset(role, beat_p: 0.5, swing: 66)
    with_env("SWING" => swing.to_s) { send(:swing_role_offset_ms, role, beat_p) }
  end

  # The grid reference. Take it away and the leaning stops reading as feel and
  # starts reading as an unsteady tempo.
  def test_both_spellings_of_the_kick_are_locked_to_the_grid
    assert_equal 0.0, SWING_ROLE_SCALE.fetch(:kick_anchor)
    assert_equal 0.0, SWING_ROLE_SCALE.fetch(:kick),
                 "a bare :kick role swinging at the fallback is the same drum swung two ways"
    assert_in_delta 0.0, offset(:kick), 1e-9
    assert_in_delta 0.0, offset(:kick_anchor), 1e-9
  end

  # Every role the engine actually names must be in the table; the fallback is
  # not a default, it is a silent misclassification.
  def test_every_named_role_has_an_entry
    missing = (DRUM_ROLES + SUSTAINED_ROLES + LEAD_ROLES).reject { |r| SWING_ROLE_SCALE.key?(r) }
    assert_empty missing, "these roles fall through to the hi-hat's lean: #{missing.inspect}"
  end

  def test_swing_at_or_below_the_midpoint_is_straight
    assert_in_delta 0.0, offset(:snare, swing: 50), 1e-9
    assert_in_delta 0.0, offset(:snare, swing: 45), 1e-9
    assert_operator offset(:snare, swing: 51), :>, 0.0
  end

  def test_a_missing_beat_period_is_not_an_offset_of_zero_milliseconds_by_accident
    assert_equal 0.0, send(:swing_role_offset_ms, :snare, nil)
  end

  # An eighth is half a beat; a swing of 66 pushes the off-eighth by 16% of it.
  def test_the_offset_is_the_documented_fraction_of_the_beat
    beat_p = 0.5
    expected = ((66 - 50) / 100.0) * (beat_p * 500.0) * SWING_ROLE_SCALE[:snare] * SWING_ROLE_SPREAD
    assert_in_delta expected, offset(:snare, beat_p:, swing: 66), 1e-9
  end

  def test_the_offset_scales_with_tempo
    slow = offset(:snare, beat_p: 1.0)
    fast = offset(:snare, beat_p: 0.5)
    assert_in_delta slow / 2.0, fast, 1e-9, "lean is a fraction of the beat, not a fixed millisecond figure"
  end

  # Shakers and maracas played deliberately late are the named source of the
  # push and pull against kick and snare.
  def test_percussion_leans_furthest_of_the_kit
    others = (DRUM_ROLES - [:perc]).map { |role| offset(role) }
    assert_operator offset(:perc), :>, others.max
  end

  # A Rhodes chord swung as hard as a shaker is the sound of a sequencer.
  def test_sustained_and_lead_voices_lean_less_than_the_hats
    hat = offset(:hat_up)
    (SUSTAINED_ROLES + LEAD_ROLES).each do |role|
      assert_operator offset(role), :<, hat, "#{role} is swung at or past the hi-hat's rate"
    end
  end

  def test_leads_sit_behind_the_pads_but_short_of_the_ghost_notes
    LEAD_ROLES.each do |role|
      assert_operator offset(role), :>=, offset(:pad), "#{role} leans less than a sustained pad"
      assert_operator offset(role), :<, offset(:ghost), "#{role} reads as late rather than lazy"
    end
  end

  def test_the_spread_knob_is_clamped_to_a_musical_range
    assert_operator SWING_ROLE_SPREAD, :>=, 0.0
    assert_operator SWING_ROLE_SPREAD, :<=, 3.0
  end

  def test_an_unknown_role_is_swung_at_the_fallback_rather_than_crashing
    assert_operator offset(:role_that_does_not_exist), :>, 0.0
  end

  # Cyclic drift is what stops a repeated bar reading as a copy-paste. `nil`
  # timing means "use MICROTIMING_MS", which is the path every render takes
  # that has not been handed a per-role override.
  def drift(bar, step = 0, role: :snare)
    with_env("SWING" => "66") { send(:cyclic_timing_offset, role, bar, step, nil, 0.5, cycle: 4) }
  end

  def test_cyclic_drift_varies_across_the_cycle_and_repeats_with_it
    assert_in_delta drift(0), drift(4), 1e-9, "the four-bar cycle does not close"
    assert_in_delta drift(1), drift(5), 1e-9

    within_cycle = (0..3).map { |bar| drift(bar) }
    assert_operator within_cycle.uniq.size, :>, 1,
                    "every bar drifts identically, which is no drift at all"
  end

  def test_drift_is_deterministic_for_a_given_position
    assert_in_delta drift(2, 3), drift(2, 3), 1e-9
  end

  def test_two_roles_do_not_drift_in_lockstep
    refute_in_delta drift(1, role: :snare), drift(1, role: :perc), 1e-9,
                    "the kit drifts as one block, which is a tempo change rather than a feel"
  end

  # No beat period means no swing and no quantisation grid: the raw microtiming
  # range is the whole answer, and it must still be a number.
  def test_drift_without_a_beat_period_is_still_a_millisecond_figure
    assert_kind_of Numeric, send(:cyclic_timing_offset, :snare, 0, 0, nil, nil, cycle: 4)
  end

  # Sonata-form phases. A gain of zero would mute a section outright; a gain
  # above one would make a section louder than the recapitulation it builds to.
  def test_phase_gain_is_a_multiplier_bounded_by_the_recapitulation
    phases = %i[exposition development recapitulation coda]
    gains = phases.to_h { |phase| [phase, send(:phase_gain_multiplier, phase)] }

    gains.each do |phase, gain|
      assert_operator gain, :>, 0.0, "#{phase} is muted outright"
      assert_operator gain, :<=, 1.0, "#{phase} is louder than the recapitulation"
    end
    assert_equal 1.0, gains[:recapitulation], "the recapitulation is the reference, not a duck"
    assert_operator gains[:coda], :<, gains[:exposition], "the coda does not fall away"
  end

  def test_an_unnamed_phase_is_unattenuated_rather_than_silent
    assert_equal 1.0, send(:phase_gain_multiplier, :not_a_phase)
    assert_equal 1.0, send(:phase_gain_multiplier, nil)
  end
end
