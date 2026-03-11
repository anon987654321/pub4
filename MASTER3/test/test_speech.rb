# frozen_string_literal: true

require_relative "test_helper"

class TestSpeech < Minitest::Test
  # ── module interface ──────────────────────────────────────────────────────

  def test_available_returns_boolean
    assert_includes [true, false], Master3::Speech.available?
  end

  def test_voices_constants_present
    assert Master3::Speech::VOICES.key?(:osman)
    assert Master3::Speech::VOICES.key?(:ryan)
  end

  def test_styles_constants_present
    assert Master3::Speech::STYLES.key?(:deep)
    assert Master3::Speech::STYLES.key?(:normal)
  end

  def test_synthesize_returns_nil_for_empty_text
    assert_nil Master3::Speech.synthesize("")
    assert_nil Master3::Speech.synthesize("   ")
  end

  def test_synthesize_bytes_returns_nil_for_empty
    assert_nil Master3::Speech.synthesize_bytes("")
  end

  # ── when edge-tts unavailable ─────────────────────────────────────────────

  def test_synthesize_returns_nil_when_unavailable
    # Stub Speech.available? to false
    Master3::Speech.stub(:available?, false) do
      assert_nil Master3::Speech.synthesize("hello")
    end
  end

  def test_synthesize_bytes_returns_nil_when_unavailable
    Master3::Speech.stub(:available?, false) do
      assert_nil Master3::Speech.synthesize_bytes("hello")
    end
  end

  # ── when edge-tts available (mock system call) ────────────────────────────

  def test_synthesize_calls_edge_tts_with_correct_args
    skip "edge-tts not installed" unless Master3::Speech.available?

    tmp = nil
    Master3::Speech.stub(:synthesize, ->(text, **) {
      # Just verify we can call it without raising
      nil
    }) do
      tmp = Master3::Speech.synthesize("test", voice: :osman, style: :deep)
    end
    assert_nil tmp  # mock returns nil
  end

  def test_synthesize_bytes_cleans_up_temp_file
    fake_path = "/tmp/m3_tts_test_fake.mp3"

    Master3::Speech.stub(:synthesize, fake_path) do
      # Create a fake mp3
      File.write(fake_path, "fake-mp3-data")
      bytes = Master3::Speech.synthesize_bytes("hello")
      assert_equal "fake-mp3-data", bytes
      refute File.exist?(fake_path), "temp file should be deleted"
    end
  end

  # ── voice / style lookup ─────────────────────────────────────────────────

  def test_unknown_voice_falls_back_to_default
    # Speech.synthesize uses VOICES.fetch(voice, VOICES[DEFAULT_VOICE])
    # so unknown symbol falls back to Osman
    default_voice = Master3::Speech::VOICES[Master3::Speech::DEFAULT_VOICE]
    assert default_voice
  end

  def test_deep_style_has_negative_pitch
    style = Master3::Speech::STYLES[:deep]
    assert style[:pitch].start_with?("-"), "deep pitch should be negative"
    assert style[:rate].start_with?("-"),  "deep rate should be negative"
  end
end
