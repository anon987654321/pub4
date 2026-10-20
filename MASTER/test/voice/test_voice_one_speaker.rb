# frozen_string_literal: true

require_relative "../test_helper"

class TestVoiceOneSpeaker < Minitest::Test
  Speech = Master::Voice::Speech
  Playback = Master::Voice::Playback

  def test_no_os_voice_speaks_by_default
    assert_equal false, Master::Voice::Policy.data["os_voice_fallback"]
    refute_predicate Speech, :os_voice_fallback?
    refute_predicate Playback, :native_say_available?
  end

  def test_a_failed_edge_sentence_is_silent_not_spoken_by_another_voice
    refuses = ->(_text) { flunk "the OS voice must not be asked" }

    Speech.stub(:edge_tts_available?, true) do
      Speech.stub(:synthesize_edge, nil) do
        Speech.stub(:synthesize_say, refuses) do
          assert_nil Speech.synthesize("a sentence that edge fails")
        end
      end
    end
  end
end
