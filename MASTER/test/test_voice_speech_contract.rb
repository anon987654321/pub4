# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"
require_relative "../lib/voice/speech"

class SpeechContractSpec < Minitest::Test
  def test_clean_text_preserves_spoken_content_while_removing_markup
    cleaned = Master::Voice::Speech.clean_text("hello `code` https://example.com ```ruby\nx\n```")
    # A URL is spoken as its host: nobody wants the scheme and path read aloud.
    assert_includes cleaned, "example.com"
    refute_includes cleaned, "https://"
    assert_includes cleaned, "code"
    assert_includes cleaned, "x"
    refute_includes cleaned, "```"
    refute_includes cleaned, "`"
  end

  def test_chunks_keep_normal_sentences_intact
    chunks = Master::Voice::Speech.chunks(
      "One sentence. Two sentence. Three sentence.",
      max: 8,
    )
    assert_equal ["One sentence.", "Two sentence.", "Three sentence."], chunks
  end

  def test_chunks_do_not_split_an_oversized_sentence_at_arbitrary_words
    sentence = "This is one deliberately long sentence that remains one thought."
    chunks = Master::Voice::Speech.chunks(sentence, max: 16)
    assert_equal [sentence], chunks
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
  def test_transcendent_engine_chain_can_be_overridden
    old = ENV["MASTER_TTS_ENGINE_CHAIN"]
    ENV["MASTER_TTS_ENGINE_CHAIN"] = "edge,say"

    cfg = Master::Voice::Transcendent.load_config
    assert_equal "edge,say", cfg["engine_chain"]
  ensure
    old.nil? ? ENV.delete("MASTER_TTS_ENGINE_CHAIN") : ENV["MASTER_TTS_ENGINE_CHAIN"] = old
  end

  def test_native_say_fallback_has_no_host_default_voice_path
    assert_equal "Samantha", Master::Voice::Engines::MACOS_VOICE_FALLBACKS.fetch(:jenny)
    assert_equal "Alex", Master::Voice::Engines::MACOS_VOICE_FALLBACKS.fetch(:andrew)
    refute Master::Voice::Engines::MACOS_VOICE_FALLBACKS.key?(:pernille)
    refute Master::Voice::Engines::MACOS_VOICE_FALLBACKS.key?(:finn)
  end
end
