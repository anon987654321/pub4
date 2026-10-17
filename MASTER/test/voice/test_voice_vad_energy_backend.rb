# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../lib/voice/vad/energy_backend"

class TestVoiceVadEnergyBackend < Minitest::Test
  def setup
    @backend = Master::Voice::Vad::EnergyBackend.new(
      energy_floor: 0.01,
      energy_ceiling: 0.20,
    )
  end

  def test_name
    assert_equal :energy, @backend.name
  end

  def test_silence_scores_zero
    assert_equal 0.0, @backend.score(Array.new(480, 0.0))
  end

  def test_loud_scores_one
    samples = Array.new(480, 0.5)
    assert_equal 1.0, @backend.score(samples)
  end

  def test_mid_range_is_interpolated
    # RMS of constant a is |a|
    samples = Array.new(480, 0.105) # just above floor 0.01 toward 0.20
    score = @backend.score(samples)
    assert score > 0.0
    assert score < 1.0
  end

  def test_accepts_precomputed_rms
    assert_equal 0.0, @backend.score([], rms: 0.0)
    assert_equal 1.0, @backend.score([], rms: 0.5)
  end
end
