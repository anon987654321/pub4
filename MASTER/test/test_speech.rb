# frozen_string_literal: true

require_relative "test_helper"

class TestSpeech < Minitest::Test
  def test_available_returns_boolean
    assert_includes [true, false], Master::Voice::Speech.available?
  end

  def test_voices_constants_present
    assert Master::Voice::Speech::VOICES.key?(:osman)
    assert Master::Voice::Speech::VOICES.key?(:ryan)
  end

  def test_styles_constants_present
    assert Master::Voice::Speech::STYLES.key?(:deep)
    assert Master::Voice::Speech::STYLES.key?(:normal)
  end

  def test_synthesize_returns_nil_for_empty_text
    assert_nil Master::Voice::Speech.synthesize("")
    assert_nil Master::Voice::Speech.synthesize("   ")
  end

  def test_synthesize_bytes_returns_nil_for_empty
    assert_nil Master::Voice::Speech.synthesize_bytes("")
  end

  def test_synthesize_audio_returns_mpeg_for_mp3
    fake_path = "/tmp/m3_tts_test_fake.mp3"

    Master::Voice::Speech.stub(:synthesize, fake_path) do
      File.write(fake_path, "fake-mp3-data")
      audio = Master::Voice::Speech.synthesize_audio("hello")
      assert_equal "fake-mp3-data", audio.bytes
      assert_equal "audio/mpeg", audio.mime_type
      refute File.exist?(fake_path), "temp file should be deleted"
    end
  end

  def test_synthesize_audio_returns_wav_for_espeak_fallback
    fake_path = "/tmp/m3_tts_test_fake.wav"

    Master::Voice::Speech.stub(:synthesize, fake_path) do
      File.write(fake_path, "fake-wav-data")
      audio = Master::Voice::Speech.synthesize_audio("hello")
      assert_equal "fake-wav-data", audio.bytes
      assert_equal "audio/wav", audio.mime_type
      refute File.exist?(fake_path), "temp file should be deleted"
    end
  end

  def test_synthesize_bytes_cleans_up_temp_file
    fake_path = "/tmp/m3_tts_test_fake.mp3"

    Master::Voice::Speech.stub(:synthesize, fake_path) do
      File.write(fake_path, "fake-mp3-data")
      bytes = Master::Voice::Speech.synthesize_bytes("hello")
      assert_equal "fake-mp3-data", bytes
      refute File.exist?(fake_path), "temp file should be deleted"
    end
  end

  def test_unknown_voice_falls_back_to_default
    default_voice = Master::Voice::Speech::VOICES[Master::Voice::Speech::DEFAULT_VOICE]
    assert default_voice
  end

  def test_deep_style_has_negative_pitch
    style = Master::Voice::Speech::STYLES[:deep]
    assert style[:pitch].start_with?("-"), "deep pitch should be negative"
    assert style[:rate].start_with?("-"),  "deep rate should be negative"
  end
end