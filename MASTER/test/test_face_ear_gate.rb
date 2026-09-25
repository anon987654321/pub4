# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/cli/face/ear"

# The face's microphone gate sits three times above the room. A fixed 0.05%
# opened on a laptop's own hiss, so every take was a sixth of a second of
# noise and the face heard nothing.
class TestFaceEarGate < Minitest::Test
  Ear = Master::CLI::Face::Ear

  def test_a_quiet_room_keeps_the_floor
    assert_in_delta 0.3, Ear.gate_for(0.04)
  end

  def test_a_laptop_hiss_puts_the_gate_above_it
    assert_in_delta 1.2, Ear.gate_for(0.4)
    assert_operator Ear.gate_for(0.4), :>, 0.4
  end

  def test_a_loud_room_still_gates_above_its_noise
    assert_in_delta 36.0, Ear.gate_for(12.0)
  end

  def test_the_ceiling_holds
    assert_in_delta 60.0, Ear.gate_for(40.0)
  end

  def test_the_take_ends_under_half_the_gate
    ear = Ear.new(device: Object.new)
    ear.instance_variable_set(:@room, 0.4)
    ear.instance_variable_set(:@room_at, Process.clock_gettime(Process::CLOCK_MONOTONIC))
    effect = ear.send(:silence_effect)
    assert_equal %w[silence 1 0.05 1.2% 1 0.8 0.6%], effect
  end
end
