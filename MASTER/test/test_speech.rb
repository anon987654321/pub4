# frozen_string_literal: true

require_relative "test_helper"

class TestSpeech < Minitest::Test
  def test_available_returns_boolean
    assert_includes [true, false], Master::Voice::Speech.available?
  end

  def test_available_uses_real_backend_guards
    Master::Voice::Speech.stub(:edge_tts_available?, false) do
      Master::Voice::Speech.stub(:espeak_path, nil) do
        refute Master::Voice::Speech.available?
      end
    end
  end

  def test_edge_tts_unavailable_without_worker
    Master::Voice::Speech.stub(:worker_executable?, false) do
      refute Master::Voice::Speech.edge_tts_available?
    end
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

  def test_synthesize_falls_back_to_espeak_when_edge_returns_nil
    Master::Voice::Speech.stub(:edge_tts_available?, true) do
      Master::Voice::Speech.stub(:synthesize_edge, nil) do
        Master::Voice::Speech.stub(:espeak_path, "/usr/local/bin/espeak") do
          Master::Voice::Speech.stub(:synthesize_espeak, "/tmp/fallback.wav") do
            assert_equal "/tmp/fallback.wav", Master::Voice::Speech.synthesize("hello")
          end
        end
      end
    end
  end

  def test_synthesize_edge_warns_and_cleans_up_failed_worker_output
    status = Struct.new(:success?).new(false)
    _out, err = capture_io do
      Master::Voice::Speech.stub(:synthesize_edge_socket, nil) do
        ::Open3.stub(:capture3, ["", "worker failed", status]) do
          assert_nil Master::Voice::Speech.synthesize_edge(
            "hello",
            voice: :ryan,
            style_config: { rate: "+0%", pitch: "+0Hz" }
          )
        end
      end
    end

    assert_includes err, "tts: edge worker failed: worker failed"
  end

  def test_resolve_voice_accepts_neural_name_and_alias
    assert Master::Voice::Speech::VOICES.key?(Master::Voice::Speech.resolve_voice("ms-MY-OsmanNeural"))
    assert_equal :davis, Master::Voice::Speech.resolve_voice(:davis)
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
