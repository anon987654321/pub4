# frozen_string_literal: true

require_relative "test_helper"

class TestVoiceNativeFallback < Minitest::Test
  def test_fix_narration_voice_has_a_native_macos_fallback
    assert_equal "Alex", Master::Voice::Engines::MACOS_VOICE_FALLBACKS.fetch(:christopher)
  end

  def test_afplay_failure_has_a_policy_native_fallback
    spoken = []

    Master::Voice::Playback.stub(:generation_active?, true) do
      Master::Voice::Playback.stub(:native_say, ->(text, **) { spoken << text; true }) do
        assert Master::Voice::Playback.send(
          :fallback_after_playback_failure,
          "hello",
          generation: 0,
        )
      end
    end

    assert_equal ["hello"], spoken
  end
end
