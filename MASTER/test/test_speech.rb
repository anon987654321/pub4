# frozen_string_literal: true

require_relative "test_helper"
require "socket"

class TestSpeech < Minitest::Test
  def test_daemon_env_strips_web_bundle_pollution
    Dir.mktmpdir("master_tts_env") do |root|
      ENV["BUNDLE_PATH"] = "/wrong/web/vendor/bundle"
      ENV["BUNDLE_GEMFILE"] = "/wrong/web/Gemfile"
      ENV["GEM_HOME"] = "/wrong/gems"
      env = Master::Voice::TtsSupervisor.daemon_env(root)
      assert_nil env["BUNDLE_PATH"]
      assert_nil env["GEM_HOME"]
      assert_equal File.join(root, "Gemfile"), env["BUNDLE_GEMFILE"]
      assert_equal ENV.fetch("HOME", ""), env["HOME"]
      assert env.values.compact.size <= Master::Voice::TtsSupervisor::SPAWN_ENV_KEYS.size + 1
    end
  ensure
    ENV.delete("BUNDLE_PATH")
    ENV.delete("BUNDLE_GEMFILE")
    ENV.delete("GEM_HOME")
  end

  # Regression: confirmed live on vm23 -- Falcon's own process has RUBYLIB
  # pointing at web's vendored bundler-4.0.7/lib and BUNDLE_LOCKFILE pointing
  # at web/Gemfile.lock. Neither was in BUNDLE_ISOLATION_KEYS, so tts-worker
  # daemons resolved web's lockfile against MASTER's Gemfile and crashed with
  # Bundler::GemNotFound on every single spawn.
  def test_daemon_env_strips_rubylib_and_bundle_lockfile_pollution
    Dir.mktmpdir("master_tts_env") do |root|
      ENV["RUBYLIB"] = "/wrong/web/vendor/bundle/ruby/3.4/gems/bundler-4.0.7/lib"
      ENV["BUNDLE_LOCKFILE"] = "/wrong/web/Gemfile.lock"
      env = Master::Voice::TtsSupervisor.daemon_env(root)
      assert_nil env["RUBYLIB"]
      assert_nil env["BUNDLE_LOCKFILE"]
    end
  ensure
    ENV.delete("RUBYLIB")
    ENV.delete("BUNDLE_LOCKFILE")
  end

  def test_daemon_env_path_is_not_inherited_from_caller
    original_path = ENV["PATH"]
    ENV["PATH"] = "/wrong/web/vendor/bundle/ruby/3.4/bin:/usr/local/bin"
    env = Master::Voice::TtsSupervisor.daemon_env(Master::ROOT)
    refute_includes env["PATH"], "vendor/bundle"
  ensure
    ENV["PATH"] = original_path
  end

  def test_tts_supervisor_health_check_uses_ping_without_synthesis
    Dir.mktmpdir("master_tts_health") do |root|
      socket_path = File.join(root, "tts.sock")
      server = UNIXServer.new(socket_path)
      responder = Thread.new do
        client = server.accept
        request = client.gets
        client.write("ok\n")
        client.close
        request
      end

      assert Master::Voice::TtsSupervisor.socket_alive?(socket_path)
      assert_equal "{\"health\":true}\n", responder.value
    ensure
      server&.close
    end
  end

  def test_available_returns_boolean
    assert_includes [true, false], Master::Voice::Speech.available?
  end

  def test_available_uses_real_backend_guards
    Master::Voice::Speech.stub(:edge_tts_available?, false) do
      Master::Voice::Speech.stub(:espeak_path, nil) do
        Master::Voice::Speech.stub(:say_available?, false) do
          refute Master::Voice::Speech.available?
        end
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

  def test_synthesize_falls_back_to_say_when_edge_and_espeak_miss
    Master::Voice::Speech.stub(:try_transcendent_synthesis, [false, nil]) do
      Master::Voice::Speech.stub(:available?, true) do
        Master::Voice::Speech.stub(:edge_tts_available?, false) do
          Master::Voice::Speech.stub(:espeak_path, nil) do
            Master::Voice::Speech.stub(:synthesize_say, "/tmp/say-fallback.mp3") do
              assert_equal "/tmp/say-fallback.mp3", Master::Voice::Speech.synthesize("hello")
            end
          end
        end
      end
    end
  end

  def test_synthesize_edge_socket_treats_eof_as_success
    path = File.join(Dir.tmpdir, "m3_socket_eof_tts_test.mp3")
    audio = "fake-mp3-bytes"
    Dir.mktmpdir("master_tts_sock") do |root|
      socket_path = File.join(root, "tts.sock")
      server = UNIXServer.new(socket_path)
      server_thread = Thread.new do
        client = server.accept
        line = client.gets
        client.write(audio)
        client.close
        line
      end
      Master::Voice::TtsSupervisor.stub(:next_socket, socket_path) do
        result = Master::Voice::Speech.synthesize_edge_socket(
          text: "hello",
          voice_name: "en-GB-RyanNeural",
          style_config: { rate: "+0%", pitch: "+0Hz" },
          audio_path: path,
        )
        assert_equal path, result
        assert_equal audio, File.binread(path)
      end
      server_thread.join
    ensure
      server&.close
    end
  ensure
    File.delete(path) if File.exist?(path)
  end

  def test_synthesize_streaming_falls_back_to_oneshot_when_socket_fails
    path = File.join(Dir.tmpdir, "m3_stream_tts_test.mp3")
    status = Struct.new(:success?).new(true)
    Master::Voice::Speech.stub(:edge_tts_available?, true) do
      Master::Voice::Speech.stub(:synthesize_edge_socket, nil) do
        Master::Io::Exec.stub(:capture3, lambda { |*_args, **_kwargs|
          File.binwrite(path, "fake-mp3-data")
          ["", "", status]
        }) do
          assert Master::Voice::Speech.synthesize_streaming_to_file(
            "hello",
            output_path: path,
            voice: :ryan,
            style: :neutral,
          )
          assert_equal "fake-mp3-data", File.binread(path)
        end
      end
    end
  ensure
    File.delete(path) if File.exist?(path)
  end

  def test_synthesize_edge_warns_and_cleans_up_failed_worker_output
    status = Struct.new(:success?).new(false)
    _out, err = capture_io do
      Master::Voice::Speech.stub(:synthesize_edge_socket, nil) do
        Master::Io::Exec.stub(:capture3, ["", "worker failed", status]) do
          assert_nil Master::Voice::Speech.synthesize_edge(
            "hello",
            voice: :ryan,
            style_config: { rate: "+0%", pitch: "+0Hz" },
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

  def test_worker_timeout_scales_with_text_length
    base = Master::Voice::Speech.send(:worker_timeout, 0)
    long = Master::Voice::Speech.send(:worker_timeout, Master::Voice::Speech::MAX_CHARS)
    assert_equal Master::Voice::Speech::WORKER_TIMEOUT, base
    assert long > base, "a full MAX_CHARS utterance should get more time than an empty one"
    assert long <= Master::Voice::Speech::WORKER_TIMEOUT_MAX
  end

  def test_worker_timeout_respects_explicit_env_override_regardless_of_length
    ENV["MASTER_TTS_TIMEOUT"] = "7"
    assert_equal 7, Master::Voice::Speech.send(:worker_timeout, Master::Voice::Speech::MAX_CHARS)
  ensure
    ENV.delete("MASTER_TTS_TIMEOUT")
  end

  # StrunkPass (lib/voice/strunk_pass.rb) had zero callers anywhere until
  # wired into clean_text here -- the actual enforcement for
  # master_output_format's "never use: Certainly, Of course..." prompt rule,
  # which nothing previously verified on the TTS output side.
  def test_clean_text_strips_sycophancy_prefix
    result = Master::Voice::Speech.clean_text("Certainly! Here is the answer.")
    refute_match(/\Acertainly/i, result)
    assert_includes result, "Here is the answer"
  end

  def test_clean_text_strips_hedge_words
    result = Master::Voice::Speech.clean_text("This will improve performance.")
    refute_includes result, "will"
  end

  def test_clean_text_preserves_newline_to_period_pacing
    result = Master::Voice::Speech.clean_text("First line no period\nSecond line no period")
    assert_equal "First line no period. Second line no period", result
  end
end
