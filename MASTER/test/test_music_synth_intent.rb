# frozen_string_literal: true

require_relative "test_helper"

class TestMusicSynthIntent < Minitest::Test
  def test_routes_waveform_requests_to_native_synth
    seen = nil
    captured_path = nil
    Master::Music::Synth.stub(:render, ->(shape:, hz:, destination:) do
      seen = [shape, hz]
      captured_path = destination
      destination
    end) do
      result = Master::Io::MediaIntent.dispatch("play a square wave")
      assert result.ok?
      assert_equal [:square, 440.0], seen
      assert_equal captured_path, result.value[:path]
    end
  end

  def test_deep_tone_uses_low_pitch
    seen = nil
    Master::Music::Synth.stub(:render, ->(shape:, hz:, destination:) do
      seen = hz
      destination
    end) do
      Master::Io::MediaIntent.dispatch("play a deep sine wave")
    end
    assert_equal 110.0, seen
  end
end
