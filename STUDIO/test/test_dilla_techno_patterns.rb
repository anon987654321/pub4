# frozen_string_literal: true

require_relative "dilla_helper"

# The techno drum profiles are data: one seed must give one cycle, the
# four-on-the-floor profiles must keep a kick on every beat, the offbeat hat
# must sit on the "and", and no role may lean further than MICRO_MAX_STEPS.
class TestDillaTechnoPatterns < Minitest::Test
  P = DillaTechnoPatterns

  def test_there_are_at_least_five_named_profiles
    assert_operator P.names.length, :>=, 5
    assert_includes P.names, :fjaak_broken
    assert_includes P.names, :klock_rolling
  end

  def test_same_seed_same_cycle_and_pick
    P.names.each { |n| assert_equal P.cycle(n, 42), P.cycle(n, 42) }
    assert_equal P.pick(7), P.pick(7)
    refute_equal P.cycle(:klock_rolling, 1), P.cycle(:klock_rolling, 2)
  end

  def test_four_on_floor_profiles_kick_every_beat
    P.names.select { |n| P.four_on_floor?(n) }.each do |n|
      rows = P.cycle(n, 3)
      P::BARS.times do |bar|
        steps = rows[:kick][bar].map { |s, _| s.round }
        # The last bar of the driving profile may drop its fourth kick as a turnaround.
        beats = (n == :driving_offbeat && bar == P::BARS - 1) ? [0, 4, 8] : P::FLOOR
        assert_empty beats - steps, "#{n} bar #{bar} lacks a kick on the beat"
      end
    end
  end

  def test_broken_profile_is_not_four_on_floor
    refute P.four_on_floor?(:fjaak_broken)
    refute_equal P::FLOOR, P.cycle(:fjaak_broken, 3)[:kick][0].map { |s, _| s.round }
  end

  def test_offbeat_hat_lands_on_the_and
    rows = P.cycle(:driving_offbeat, 5)
    rows[:open].each do |bar|
      assert_equal P::OFFBEATS, bar.map { |s, _| s.round }
      bar.each { |s, _| assert_in_delta s.round, s, P::MICRO_MAX_STEPS }
    end
  end

  def test_micro_timing_is_bounded_and_kicks_stay_on_grid
    P.names.each do |n|
      P.cycle(n, 9).each do |role, bars|
        bars.flatten(1).each do |step, vel|
          assert_operator (step - step.round).abs, :<=, P::MICRO_MAX_STEPS + 1e-9, "#{n} #{role}"
          assert_operator vel, :>, 0.0
          assert_operator vel, :<=, 1.0
          assert_equal step.round, step if role == :kick
        end
      end
    end
  end

  def test_klock_swings_odd_sixteenths_late
    hats = P.cycle(:klock_rolling, 11)[:hat].flatten(1)
    odd = hats.select { |s, _| s.round.odd? }
    assert odd.all? { |s, _| s > s.round }, "odd 16ths should lean late"
  end

  def test_pattern_name_honours_env_and_seed
    assert_includes P.names, with_env("TECHNO_PATTERN" => "", "RENDER_SEED" => "5") { send(:techno_pattern_name) }
    assert_equal :regis_industrial, with_env("TECHNO_PATTERN" => "regis_industrial") { send(:techno_pattern_name) }
  end
end
