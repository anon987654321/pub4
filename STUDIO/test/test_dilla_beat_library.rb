# frozen_string_literal: true

require_relative "dilla_helper"

# The boom-bap library is data the hiphop render path reads. These tests hold
# the properties that make it hip-hop: a repeatable pick, a backbeat on 2 and 4,
# and per-instrument lean that stays inside stated bounds.
class TestDillaBeatLibrary < Minitest::Test
  Lib = DillaBeatLibrary

  def teardown
    Lib.deactivate!
  end

  def test_same_seed_gives_same_pattern
    10.times { |seed| assert_equal Lib.pick_name(seed), Lib.pick_name(seed) }
    assert_equal Lib.steps_for(:kicks, 3, Lib.pick_name(7)), Lib.steps_for(:kicks, 3, Lib.pick_name(7))
  end

  def test_seeds_reach_every_pattern
    assert_equal Lib.names, (0...Lib.names.length).map { |s| Lib.pick_name(s) }.sort
  end

  def test_every_pattern_has_a_snare_on_two_and_four_in_every_bar
    Lib.names.each do |name|
      8.times do |bar|
        snares = Lib.steps_for(:snares, bar, name)
        assert_includes snares, 4, "#{name} bar #{bar} lacks the snare on 2"
        assert_includes snares, 12, "#{name} bar #{bar} lacks the snare on 4"
      end
    end
  end

  def test_every_pattern_anchors_the_downbeat_with_a_kick
    Lib.names.each do |name|
      4.times { |bar| assert_includes Lib.steps_for(:kicks, bar, name), 0, name }
    end
  end

  def test_steps_stay_on_the_sixteen_step_grid
    Lib.names.each do |name|
      %i[kicks snares hats ghosts].each do |role|
        4.times { |bar| assert Lib.steps_for(role, bar, name).all? { |s| (0..15).cover?(s) }, "#{name} #{role}" }
      end
    end
  end

  def test_tick_offsets_stay_inside_the_stated_bounds
    Lib.names.each do |name|
      { kick: :kick, snare: :snare, hat: :hat_down, ghost: :ghost }.each do |inst, role|
        lo, hi = Lib::BOUNDS.fetch(inst)
        16.times do |step|
          ticks = Lib.tick_offset(role, step, name)
          assert_kind_of Integer, ticks
          assert_includes lo..hi, ticks, "#{name} #{inst} step #{step}"
        end
      end
    end
  end

  def test_the_snare_sits_behind_the_kick
    Lib.names.each do |name|
      assert_operator Lib.tick_offset(:snare, 4, name), :>, Lib.tick_offset(:kick, 0, name), name
    end
  end

  def test_kick_snare_and_hat_do_not_share_one_grid
    Lib.names.reject { |n| n == "premier_knock" }.each do |name|
      lean = %i[kick snare hat_down].map { |role| Lib.tick_offset(role, 1, name) }
      assert_operator lean.uniq.length, :>, 1, name
    end
  end

  def test_no_pattern_active_means_no_override
    assert_nil Lib.steps_for(:kicks, 0)
    assert_nil Lib.tick_offset(:snare, 4)
  end

  def test_active_pattern_drives_the_engine_pick_and_timing
    name = Lib.activate!(2)
    assert_equal Lib.steps_for(:kicks, 1, name), drum_pattern_pick(1, :default, :kicks)
    beat_p = 0.625
    expected = beat_p / 96.0 * Lib.tick_offset(:snare, 4, name)
    with_env("SWING" => "56") do
      assert_in_delta expected, DillaGroove.role_timing_offset(:snare, beat_p, 0, 4), 1e-9
    end
  end
end
