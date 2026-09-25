# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"
require_relative "../lib/voice/speech"

class SpeechContractSpec < Minitest::Test
  def test_clean_text_preserves_spoken_content_while_removing_markup
    cleaned = Master::Voice::Speech.clean_text("hello `code` https://example.com ```ruby\nx\n```")
    assert_includes cleaned, "https://example.com"
    assert_includes cleaned, "code"
    assert_includes cleaned, "x"
    refute_includes cleaned, "```"
    refute_includes cleaned, "`"
  end

  def test_chunks_respect_sentence_boundaries
    chunks = Master::Voice::Speech.chunks("One sentence. Two sentence. Three sentence.", max: 24)
    assert_operator chunks.length, :>=, 2
    assert chunks.all? { |chunk| chunk.length <= 24 }
  end

  def test_voice_and_style_are_env_configurable
    old_voice = ENV["MASTER_TTS_VOICE"]
    old_style = ENV["MASTER_TTS_STYLE"]
    ENV["MASTER_TTS_VOICE"] = "finn"
    ENV["MASTER_TTS_STYLE"] = "calm"
    assert_equal :finn, Master::Voice::Speech.default_voice
    assert_equal :calm, Master::Voice::Speech.default_style
  ensure
    ENV["MASTER_TTS_VOICE"] = old_voice
    ENV["MASTER_TTS_STYLE"] = old_style
  end
end
