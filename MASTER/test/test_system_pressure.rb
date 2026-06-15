# frozen_string_literal: true

require_relative "test_helper"

class TestSystemPressure < Minitest::Test
  def test_memory_pressure_uses_openbsd_thresholds
    thresholds = { "mem_free_pct" => { "warn" => 20, "crit" => 10 } }
    assert Master::Loop::SystemPressure.memory_pressure?(5.0, thresholds)
    refute Master::Loop::SystemPressure.memory_pressure?(25.0, thresholds)
  end

  def test_sample_includes_memory_pressure_flag
    sample = Master::Loop::SystemPressure.sample
    assert sample.key?(:mem_free_pct)
    assert sample.key?(:memory_pressure)
    assert sample.key?(:thresholds)
  end
end