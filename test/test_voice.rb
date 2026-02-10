require 'minitest/autorun'
require_relative '../lib/voice'

class TestVoice < Minitest::Test
  def test_voice_nlu_parse_refactor
    result = MASTER::VoiceNLU.parse("refactor lib/engine.rb")
    
    assert_equal :refactor, result[:action]
    assert_equal "lib/engine.rb", result[:target]
  end

  def test_voice_nlu_parse_analyze
    result = MASTER::VoiceNLU.parse("analyze lib/engine.rb")
    
    assert_equal :analyze, result[:action]
    assert_equal "lib/engine.rb", result[:target]
  end

  def test_voice_nlu_parse_suggest
    result = MASTER::VoiceNLU.parse("show code smells in lib/")
    
    assert_equal :suggest, result[:action]
    assert_equal "lib/", result[:target]
  end

  def test_voice_nlu_parse_fix_all
    result = MASTER::VoiceNLU.parse("fix all")
    
    # Should map to refactor since fix_all is not implemented
    assert_equal :refactor, result[:action]
  end

  def test_voice_initialization
    voice = MASTER::Voice.new(wake_word: "hey test", language: "en-US")
    
    assert_equal "hey test", voice.wake_word
    refute voice.listening
  end

  def test_speak
    voice = MASTER::Voice.new
    
    # Should return the text
    result = voice.speak("Hello world")
    assert_equal "Hello world", result
  end

  def test_transcribe
    voice = MASTER::Voice.new
    
    # Simulated transcription
    result = voice.transcribe("audio.mp3")
    
    assert_kind_of Hash, result
    assert result.key?(:text)
    assert result.key?(:confidence)
  end
end
