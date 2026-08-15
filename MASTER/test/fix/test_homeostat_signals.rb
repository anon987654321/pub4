# frozen_string_literal: true

require_relative "../test_helper"

# The homeostat's two reader mixins, which nothing tested.
#
# They are read in three places -- the persona prompt, the model selector, and
# the summary line -- and every one of them consumes the return value directly.
# `Personality::MOOD_LINES[@homeostat.mood]` puts a blank line in the prompt when
# mood is nil, and PersonalityPromptBuilder joins the result, so the gap was
# invisible in every output it reached.
class TestHomeostatSignals < Minitest::Test
  H = Master::Fix::Homeostat

  def homeostat(**overrides)
    unit = H.new
    state = unit.instance_variable_get(:@state)
    overrides.each { |drive, value| state[drive] = value }
    unit
  end

  # --- health predicates --------------------------------------------------

  def test_a_fresh_homeostat_sits_at_its_setpoints_and_is_healthy
    unit = H.new

    assert_equal :healthy, unit.health_status
    assert unit.healthy?
    refute unit.degraded?
    refute unit.critical?
  end

  def test_each_drive_can_reach_degraded_on_its_own
    { error_rate: 0.25, fatigue: 0.6 }.each do |drive, edge|
      assert_equal :degraded, homeostat(drive => edge).health_status, "#{drive} at its edge is not degraded"
    end
    assert_equal :degraded, homeostat(energy: 0.35).health_status, "a low energy floor is not degraded"
  end

  def test_each_drive_can_reach_critical_on_its_own
    { error_rate: 0.50, fatigue: 0.8 }.each do |drive, edge|
      assert_equal :critical, homeostat(drive => edge).health_status, "#{drive} at its edge is not critical"
    end
    assert_equal :critical, homeostat(energy: 0.20).health_status
  end

  # The thresholds are `>=` on pressure and `<=` on energy. One drive being at
  # its edge and another being past it must not read as healthy.
  def test_the_edges_are_inclusive
    thresholds = H::HEALTH_THRESHOLDS

    assert homeostat(error_rate: thresholds[:degraded][:error_rate]).degraded?
    refute homeostat(error_rate: thresholds[:degraded][:error_rate] - 0.01).degraded?
    assert homeostat(energy: thresholds[:critical][:energy]).critical?
  end

  # degraded? short-circuits on critical?, so the two are exclusive by
  # construction. A state that is past both edges is critical and only critical.
  def test_critical_outranks_degraded
    unit = homeostat(error_rate: 0.9, fatigue: 0.9, energy: 0.05)

    assert unit.critical?
    refute unit.degraded?
    refute unit.healthy?
    assert_equal :critical, unit.health_status
  end

  def test_health_status_is_always_one_of_three
    assert_includes %i[healthy degraded critical], homeostat(fatigue: 0.65).health_status
    assert_includes %i[healthy degraded critical], H.new.health_status
  end

  # --- mood ---------------------------------------------------------------

  # Personality::MOOD_LINES declares four. Before this, mood returned two of
  # them plus nil, and MOOD_LINES[nil] is nil -- a blank line inside
  # <master_runtime_state> where the mood belonged.
  def test_every_declared_mood_is_reachable
    reachable = {
      tense: homeostat(error_rate: 0.5),
      weary: homeostat(fatigue: 0.7),
      curious: homeostat(novelty_hunger: 0.7),
      focused: H.new,
    }.transform_values(&:mood)

    assert_equal %i[tense weary curious focused].sort, reachable.values.sort
    reachable.each { |expected, actual| assert_equal expected, actual }
  end

  def test_no_state_produces_a_moodless_prompt
    lines = Master::Voice::Personality::MOOD_LINES

    [H.new, homeostat(error_rate: 0.9), homeostat(fatigue: 0.9),
     homeostat(novelty_hunger: 1.0), homeostat(energy: 0.0)].each do |unit|
      refute_nil unit.mood, "a state with no mood puts a blank line in the persona prompt"
      refute_nil lines[unit.mood], "mood #{unit.mood.inspect} has no line in Personality::MOOD_LINES"
    end
  end

  def test_error_pressure_outranks_fatigue_and_curiosity
    assert_equal :tense, homeostat(error_rate: 0.5, fatigue: 0.9, novelty_hunger: 1.0).mood
  end

  def test_fatigue_outranks_curiosity
    assert_equal :weary, homeostat(fatigue: 0.7, novelty_hunger: 1.0).mood
  end

  # "weary" and "degraded by fatigue" are the same claim; two constants for one
  # idea drift.
  def test_weary_starts_where_fatigue_degrades
    edge = H::HEALTH_THRESHOLDS[:degraded][:fatigue]

    assert_equal :weary, homeostat(fatigue: edge).mood
    refute_equal :weary, homeostat(fatigue: edge - 0.01).mood
  end

  # --- circadian phase ----------------------------------------------------

  def test_every_hour_of_the_day_resolves_to_a_declared_phase
    lines = Master::Voice::Personality::PHASE_LINES
    unit = H.new

    seen = (0..23).map do |hour|
      phase = Time.stub(:now, Time.new(2026, 8, 16, hour, 0, 0)) { unit.circadian_phase }
      refute_nil phase, "hour #{hour} has no phase, so the prompt loses its phase line"
      refute_nil lines[phase], "phase #{phase.inspect} has no line in Personality::PHASE_LINES"
      phase
    end

    assert_equal lines.keys.sort, seen.uniq.sort, "a declared phase is unreachable"
  end

  def test_the_bands_are_contiguous_and_do_not_overlap
    unit = H.new
    at = ->(hour) { Time.stub(:now, Time.new(2026, 8, 16, hour, 0, 0)) { unit.circadian_phase } }

    assert_equal :night, at.call(4)
    assert_equal :morning, at.call(5)
    assert_equal :morning, at.call(11)
    assert_equal :afternoon, at.call(12)
    assert_equal :afternoon, at.call(17)
    assert_equal :evening, at.call(18)
    assert_equal :evening, at.call(22)
    assert_equal :night, at.call(23)
  end

  # (23..4) covers nothing, which is why night is the fallback rather than a
  # range. Both ends of the wrap have to answer.
  def test_night_wraps_midnight
    unit = H.new
    [23, 0, 1, 4].each do |hour|
      assert_equal :night, Time.stub(:now, Time.new(2026, 8, 16, hour, 0, 0)) { unit.circadian_phase }
    end
  end

  # --- tier bias ----------------------------------------------------------

  def test_a_healthy_homeostat_does_not_bias_the_model_tier
    assert_equal :default, H.new.model_tier_bias
  end

  def test_error_pressure_or_fatigue_drops_to_the_cheap_tier
    assert_equal :cheap, homeostat(error_rate: 0.5).model_tier_bias
    assert_equal :cheap, homeostat(fatigue: 0.8).model_tier_bias
  end

  # The selector reads this and nothing else, so an unrecognised value is a
  # silent no-op there rather than an error.
  def test_the_bias_is_always_a_tier_the_selector_knows
    [H.new, homeostat(error_rate: 1.0), homeostat(fatigue: 1.0), homeostat(energy: 0.0)].each do |unit|
      assert_includes %i[default cheap], unit.model_tier_bias
    end
  end

  # --- the composite readers ---------------------------------------------

  def test_the_summary_names_every_signal_and_leaves_none_blank
    line = H.new.summary

    assert_match(/mood=\w+/, line)
    assert_match(/phase=\w+/, line)
    assert_match(/health=\w+/, line)
    refute_match(/=\s|=$/, line, "a signal returned nil and the summary printed an empty field")
  end

  def test_to_h_carries_the_state_and_all_three_derived_signals
    snapshot = H.new.to_h

    assert_equal H::DRIVES.keys.sort, snapshot.fetch(:state).keys.sort
    %i[mood phase tier health].each { |key| refute_nil snapshot[key], "#{key} is nil in the snapshot" }
  end

  def test_the_snapshot_is_a_copy_rather_than_the_live_state
    unit = H.new
    snapshot = unit.to_h
    snapshot[:state][:energy] = 99.0

    refute_equal 99.0, unit.state[:energy], "a reader can write the drive state through its own snapshot"
  end

  # --- observation feeds the signals -------------------------------------

  def test_a_run_of_failures_reaches_tense_and_the_cheap_tier
    unit = H.new
    6.times { unit.observe(:llm_failure) }

    assert_equal :tense, unit.mood
    assert_equal :cheap, unit.model_tier_bias
    refute unit.healthy?
  end

  def test_every_declared_event_is_observable
    unit = H.new
    H::EVENT_DELTAS.each_key do |event|
      assert_kind_of Hash, unit.observe(event), "#{event} is declared and cannot be observed"
    end
  end

  def test_an_unknown_event_decays_rather_than_raising
    assert_kind_of Hash, H.new.observe(:an_event_nobody_declared)
  end

  def test_drives_stay_inside_their_bounds_under_pressure
    unit = H.new
    40.times { unit.observe(:llm_failure) }
    40.times { unit.observe(:llm_call) }

    unit.state.each do |drive, value|
      assert_operator value, :>=, 0.0, "#{drive} went negative"
      assert_operator value, :<=, 1.0, "#{drive} exceeded one"
    end
  end
end
