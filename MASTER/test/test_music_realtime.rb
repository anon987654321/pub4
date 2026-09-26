# frozen_string_literal: true

require_relative "test_helper"
require "master"

class TestMusicRealtime < Minitest::Test
  SHAPES = %i[sine square triangle].freeze

  def test_each_shape_stays_in_range_across_a_full_cycle
    SHAPES.each do |shape|
      1_000.times do |i|
        t = i / 1_000.0
        value = Master::Music::Synth.oscillator(shape, 1.0, t)
        assert_operator value, :>=, -1.0, "#{shape} at t=#{t}"
        assert_operator value, :<=, 1.0, "#{shape} at t=#{t}"
      end
    end
  end

  def test_sine_matches_the_math_library
    assert_in_delta Math.sin(Math::PI / 2), Master::Music::Synth.oscillator(:sine, 1.0, 0.25), 0.000_001
  end

  def test_square_is_bang_bang
    assert_equal 1.0, Master::Music::Synth.oscillator(:square, 1.0, 0.0)
    assert_equal(-1.0, Master::Music::Synth.oscillator(:square, 1.0, 0.5))
  end

  # 4*phase-1 below 0.5, 3-4*phase from 0.5: -1 at phase 0, rising to +1 at
  # phase 0.5 (the peak), falling back to -1 at phase 1.
  def test_triangle_peaks_at_the_half_point
    assert_in_delta(-1.0, Master::Music::Synth.oscillator(:triangle, 1.0, 0.0), 0.000_001)
    assert_in_delta 1.0, Master::Music::Synth.oscillator(:triangle, 1.0, 0.5), 0.000_001
  end

  def test_morph_sample_stays_in_range_through_every_crossfade
    2_000.times do |i|
      t = i / 2_000.0 * 3.0
      value = Master::Music::Realtime.morph_sample(SHAPES, 1.0, t, 1.0, 0.2)
      assert_operator value, :>=, -1.0, "t=#{t}"
      assert_operator value, :<=, 1.0, "t=#{t}"
    end
  end

  # The crossfade weight sweeps linearly 0 -> 1 across the fade window, so
  # consecutive samples inside it cannot jump by more than one shape's own
  # worst-case single-sample delta (square's instantaneous 2.0 swing) --
  # the blend cannot introduce a *larger* discontinuity than either pure
  # waveform already has at its own transition.
  def test_the_crossfade_introduces_no_jump_larger_than_a_pure_shape_has
    max_pure_delta = 2.0 # square's own -1 -> 1 step
    samples = (0..4_000).map { |i| Master::Music::Realtime.morph_sample(SHAPES, 1.0, i / 4_000.0 * 3.0, 1.0, 0.2) }
    samples.each_cons(2) do |a, b|
      assert_operator (b - a).abs, :<=, max_pure_delta + 0.000_001
    end
  end

  def test_morph_sample_before_any_crossfade_is_the_pure_current_shape
    value = Master::Music::Realtime.morph_sample(SHAPES, 1.0, 0.0, 1.0, 0.2)
    assert_equal Master::Music::Synth.oscillator(:sine, 1.0, 0.0), value
  end

  def test_stream_player_discovery_works_from_a_minimal_path
    Dir.mktmpdir do |dir|
      sox = File.join(dir, "sox")
      File.write(sox, "#!/bin/sh\n")
      File.chmod(0o755, sox)
      old_path = ENV["PATH"]
      ENV["PATH"] = dir
      assert_equal true, Master::Music::AudioSink.which("sox")
    ensure
      ENV["PATH"] = old_path
    end
  end

  def test_unavailable_player_raises_rather_than_silently_dropping_audio
    assert_raises(Master::Music::AudioSink::NoPlayerError) { Master::Music::AudioSink.new(player: nil) }
  end
end
