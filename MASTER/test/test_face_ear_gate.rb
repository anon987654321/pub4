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

  # A room at 0.4% gates at 1.2%, about 393 of 32768.
  def ear_with(stream, transcriber)
    ear = Ear.new(device: Object.new, capture: -> { stream }, transcriber:)
    ear.instance_variable_set(:@room, 0.4)
    ear.instance_variable_set(:@room_at, Process.clock_gettime(Process::CLOCK_MONOTONIC))
    ear
  end

  def hiss(count) = Array.new(count) { rand(-60..60) }

  # Half a second of hiss, two seconds of a loud tone, a second of hiss.
  def room_then_speech
    tone = Array.new(32_000) { |i| (8_000 * Math.sin(i * 0.2)).round }
    StringIO.new((hiss(8_000) + tone + hiss(16_000)).pack("s<*"))
  end

  def listen(ear, heard = [])
    ear.send(:host_listen, stop: -> { false }, on_partial: ->(text) { heard << text })
  end

  def test_the_take_is_the_speech_and_not_the_room
    heard = []
    text = listen(ear_with(room_then_speech, ->(pcm) { "#{pcm.bytesize} bytes" }), heard)
    assert_operator text.to_i, :>=, 64_000, "the take lost the speech"
    assert_operator text.to_i, :<, 64_000 + 32_000, "the take ran on through the quiet"
    assert_equal text, heard.last, "the final words were not the last shown"
  end

  def test_words_arrive_while_the_take_is_still_going
    sizes = Queue.new
    ear = ear_with(room_then_speech, ->(pcm) { sizes << pcm.bytesize; "so far" })
    listen(ear)
    ear.instance_variable_get(:@worker)&.join
    seen = []
    seen << sizes.pop until sizes.empty?
    assert_operator seen.size, :>=, 2, "only the final transcript was asked for"
    assert_operator seen.min, :<, seen.max, "no interim came before the take ended"
  end

  def test_a_silent_room_hears_nothing
    quiet = StringIO.new(hiss(32_000).pack("s<*"))
    assert_nil listen(ear_with(quiet, ->(_) { flunk "transcribed a silent room" }))
  end
end
