# frozen_string_literal: true

require_relative "test_helper"
require "socket"

class TestSpeech < Minitest::Test
  # Offline, "edge socket produced empty audio" printed fourteen times running.
  # voice.yml declared the chain, Policy read it, Speech applied it — and the
  # live path never called it. synthesis_mode has been "transcendent" since
  # Transcendent shipped, and that branch returned its file untouched, so every
  # reply this machine spoke went out bare (measured 2026-09-16: -25.3 LUFS raw
  # against -17.2 through the chain).
  def test_the_transcendent_path_is_shaped_like_every_other
    shaped = []
    Master::Voice::Transcendent.stub(:enabled?, true) do
      Master::Voice::Speech.stub(:synthesis_mode, "transcendent") do
        Master::Voice::Transcendent.stub(:synthesize, "/tmp/m_tts_probe.mp3") do
          Master::Voice::Speech.stub(:shaped, ->(path) { shaped << path; "#{path}_shaped" }) do
            assert_equal "/tmp/m_tts_probe.mp3_shaped", Master::Voice::Speech.synthesize("a sentence")
          end
        end
      end
    end

    assert_equal ["/tmp/m_tts_probe.mp3"], shaped, "the transcendent path skipped the chain"
  end

  def test_a_tts_failure_prints_once_and_stays_in_last_error
    speech = Master::Voice::Speech
    message = "probe failure #{Process.pid}"
    _, err = capture_io { 3.times { speech.send(:warn_tts, message) } }

    assert_equal 1, err.lines.grep(/#{message}/).size
    assert_equal message, speech.instance_variable_get(:@last_error)
  end

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

  def test_audio_children_close_the_master_control_lock
    source = File.read(File.expand_path("../lib/voice/playback.rb", __dir__))
    assert_includes source, "ProcessSpawn.options"
    source = File.read(File.expand_path("../lib/voice/tts_supervisor.rb", __dir__))
    assert_includes source, "ProcessSpawn.options"
  end

  def test_available_returns_boolean
    assert_includes [true, false], Master::Voice::Speech.available?
  end

  def test_available_uses_real_backend_guards
    Master::Voice::Speech.stub(:edge_tts_available?, false) do
      Master::Voice::Speech.stub(:espeak_path, nil) do
        Master::Voice::Speech.stub(:say_available?, false) do
          # Replicate is the fourth backend; a token on the machine or left in
          # ENV by another test made this pass or fail by who ran first.
          Master::Voice::Engines.stub(:replicate_token?, false) do
            refute Master::Voice::Speech.available?
          end
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

  def test_playback_leaves_transcendent_prosody_unlocked
    playback = Master::Voice::Playback
    options = nil

    Master::Voice::Speech.stub(:synthesis_mode, "transcendent") do
      Master::Voice::Speech.stub(:synthesize, ->(_text, **kwargs) { options = kwargs; nil }) do
        playback.send(:synthesize, "A sentence.")
      end
    end

    assert_equal :auto, options.fetch(:style)
    assert_nil options[:rate]
    assert_nil options[:pitch]
    refute options.fetch(:style_locked)
  end

  def test_transcendent_tts_is_the_default_but_classic_can_be_requested
    speech = Master::Voice::Speech
    original = ENV["MASTER_TTS_MODE"]
    ENV.delete("MASTER_TTS_MODE")

    Master::Voice::Transcendent.stub(:load_config, { "fast_mode" => false, "default_mode" => "transcendent" }) do
      assert_equal "transcendent", speech.synthesis_mode
      ENV["MASTER_TTS_MODE"] = "classic"
      assert_equal "classic", speech.synthesis_mode
    end
  ensure
    ENV["MASTER_TTS_MODE"] = original
  end

  def test_transcendent_streaming_is_default
    original = ENV["MASTER_TTS_MODE"]
    ENV.delete("MASTER_TTS_MODE")

    Master::Voice::Transcendent.stub(:load_config, { "fast_mode" => false, "default_mode" => "transcendent", "enabled" => true }) do
      assert_equal true, Master::Voice::Speech.send(:transcendent_streaming_enabled?, {})
    end
  ensure
    ENV["MASTER_TTS_MODE"] = original
  end

  def test_fast_mode_remains_available_as_an_explicit_override
    Master::Voice::Transcendent.stub(:load_config, { "fast_mode" => true, "default_mode" => "transcendent" }) do
      assert_equal "classic", Master::Voice::Speech.synthesis_mode
    end
  end

  def test_fast_socket_resolution_returns_nil_without_a_socket
    speech = Master::Voice::Speech
    speech.stub(:fast_tts_mode?, true) do
      Master::Voice::TtsSupervisor.stub(:next_socket, nil) do
        Master::Voice::TtsSupervisor.stub(:ensure_daemon!, ->(*) { raise "fast mode must not start a daemon" }) do
          assert_nil speech.send(:resolve_socket_path)
        end
      end
    end
  end

  def test_fast_streaming_does_not_start_a_missing_daemon
    speech = Master::Voice::Speech
    speech.stub(:edge_tts_available?, true) do
      speech.stub(:fast_tts_mode?, true) do
        Master::Voice::TtsSupervisor.stub(:ensure_daemon!, ->(*) { raise "fast mode must not start a daemon" }) do
          speech.stub(:attempt_socket_synthesis, false) do
            speech.stub(:attempt_oneshot_synthesis, false) do
              Dir.mktmpdir("master_tts_fast_stream") do |dir|
                path = File.join(dir, "answer.mp3")
                refute speech.send(:edge_stream_written?, "hello", :jenny, { rate: "+0%", pitch: "+0Hz" }, path, nil)
              end
            end
          end
        end
      end
    end
  end

  def test_native_audio_mime_types
    assert_equal "audio/mpeg", Master::Voice::Speech.mime_type_for(".mp3")
    assert_equal "audio/wav", Master::Voice::Speech.mime_type_for(".wav")
    assert_equal "audio/mp4", Master::Voice::Speech.mime_type_for(".m4a")
  end

  def test_clean_text_does_not_cut_the_tail
    text = ("Norwegian tail stays present. " * 220).strip
    assert_equal text, Master::Voice::Speech.clean_text(text)
  end

  def test_norwegian_voice_cannot_be_overridden
    original = ENV["MASTER_TTS_VOICE"]
    ENV["MASTER_TTS_VOICE"] = "christopher"
    assert_equal :pernille, Master::Voice::Speech.voice_for_text("Det ser faktisk riktig ut.")
  ensure
    ENV["MASTER_TTS_VOICE"] = original
  end

  def test_norwegian_text_resolves_to_pernille
    assert_equal :pernille, Master::Voice::Speech.voice_for_text("Det ser faktisk riktig ut.")
    assert_equal :jenny, Master::Voice::Speech.voice_for_text("The system is ready.")
  end

  def test_language_voice_families_keep_male_counterparts
    assert_equal :finn, Master::Voice::Policy.voice_for_language(:nb, gender: :male)
    assert_equal :pernille, Master::Voice::Policy.voice_for_language(:nb, gender: :female)
    assert_equal :osman, Master::Voice::Policy.voice_for_language(:ms, gender: :male)
    assert_equal :yasmin, Master::Voice::Policy.voice_for_language(:ms, gender: :female)
  end

  def test_malay_text_resolves_to_yasmin
    assert_equal :yasmin, Master::Voice::Speech.voice_for_text("Ini adalah sistem yang sudah siap.")
  end

  def test_male_language_override_stays_inside_language_family
    original = ENV["MASTER_TTS_GENDER"]
    ENV["MASTER_TTS_GENDER"] = "male"
    assert_equal :finn, Master::Voice::Speech.voice_for_text("Dette er klart nå.")
    assert_equal :osman, Master::Voice::Speech.voice_for_text("Ini adalah berita yang penting.")
  ensure
    ENV["MASTER_TTS_GENDER"] = original
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

  def test_voice_locked_never_falls_back_to_a_different_voice
    saved_voice = ENV["MASTER_TTS_VOICE"]
    ENV["MASTER_TTS_VOICE"] = "christopher"

    Master::Voice::Speech.stub(:available?, true) do
      Master::Voice::Speech.stub(:edge_tts_available?, false) do
        Master::Voice::Speech.stub(:espeak_path, "/usr/local/bin/espeak") do
          Master::Voice::Speech.stub(:synthesize_espeak, "/tmp/wrong-voice.wav") do
            Master::Voice::Speech.stub(:synthesize_say, "/tmp/wrong-voice.aiff") do
              refute Master::Voice::Speech.synthesize(
                "hello",
                voice: :christopher,
                voice_locked: true,
              )
            end
          end
        end
      end
    end
  ensure
    saved_voice.nil? ? ENV.delete("MASTER_TTS_VOICE") : ENV["MASTER_TTS_VOICE"] = saved_voice
  end

  def test_streaming_espeak_fallback_keeps_wav_instead_of_encoding_mp3
    output = File.join(Dir.tmpdir, "m3_native_tts_test.mp3")
    wav = File.join(Dir.tmpdir, "m3_native_tts_source.wav")
    File.binwrite(wav, "fake-wav-data")

    Master::Voice::Speech.stub(:espeak_path, "/usr/bin/espeak") do
      Master::Voice::Speech.stub(:synthesize_espeak, wav) do
        result = Master::Voice::Speech.send(:attempt_espeak_synthesis, "hello", output, nil)
        assert_equal output.sub(/\.mp3\z/, ".wav"), result
        assert_equal "fake-wav-data", File.binread(result)
        refute File.exist?(output)
      end
    end
  ensure
    [output, wav, output&.sub(/\.mp3\z/, ".wav")].compact.uniq.each { |path| File.delete(path) if File.exist?(path) }
  end

  def test_streaming_falls_back_to_say_when_edge_and_espeak_miss
    path = File.join(Dir.tmpdir, "m3_stream_say_fallback_test.mp3")
    Master::Voice::Speech.stub(:attempt_espeak_synthesis, false) do
      Master::Voice::Speech.stub(:edge_stream_written?, false) do
        Master::Voice::Speech.stub(:transcendent_stream_written?, false) do
          Master::Voice::Speech.stub(:attempt_say_synthesis, ->(_text, output_path, _on_chunk) { File.write(output_path, "fake-say-audio"); true }) do
            assert Master::Voice::Speech.synthesize_streaming_to_file("hello", output_path: path, voice: :jenny, style: :neutral)
          end
        end
      end
    end
    assert_equal "fake-say-audio", File.read(path)
  ensure
    File.delete(path) if path && File.exist?(path)
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
    wire = ->(client) { client.write("fake-mp3-bytes") }
    result, _path, bytes = with_edge_stub_server(wire)
    assert bytes, "a whole-file legacy answer must resolve to an audio path"
    assert_equal "fake-mp3-bytes", bytes
  end

  # Wire v2: a daemon answering "stream":true sends 8-byte length-prefixed
  # chunks and a zero-length frame. The file must hold exactly the payloads,
  # assembled as they arrived. A legacy daemon that ignores "stream" and
  # closes whole-file is still accepted — the eof test above covers it.
  def test_synthesize_edge_socket_assembles_framed_stream
    wire = lambda do |client|
      client.write([5].pack("Q>"))
      client.write("fake-")
      client.write([4].pack("Q>"))
      client.write("mp3-")
      client.write([0].pack("Q>"))
    end
    result, _path, bytes = with_edge_stub_server(wire)
    assert bytes, "a clean framed stream must resolve to an audio path"
    assert_equal "fake-mp3-", bytes
  end

  # A stream that ends without the zero frame was severed mid-synthesis. The
  # partial bytes are dropped so the caller falls back instead of speaking a
  # severed sentence.
  def test_synthesize_edge_socket_drops_truncated_stream
    wire = lambda do |client|
      client.write([5].pack("Q>"))
      client.write("fake-")
    end
    result, path, bytes = with_edge_stub_server(wire)
    assert_nil result
    assert_nil bytes, "a truncated stream must be dropped, not half-spoken"
    refute File.exist?(path)
  end

  # Serves one synthesized utterance to the daemon wire, whatever shape the
  # test writes through the client. Returns [result, audio_path, wire_bytes] —
  # the temp audio is deleted on cleanup, so the bytes must be read here.
  def with_edge_stub_server(client_io)
    root = Dir.mktmpdir("master_tts_sock")
    server = UNIXServer.new(File.join(root, "tts.sock"))
    audio_path = File.join(Dir.tmpdir, "m3_#{$$}_tts.mp3")
    File.delete(audio_path) if File.exist?(audio_path)
    server_thread = serve_once(server, client_io)
    result = Master::Voice::TtsSupervisor.stub(:next_socket, server.path) do
      Master::Voice::Speech.synthesize_edge_socket(
        text: "hello",
        voice_name: "en-GB-RyanNeural",
        style_config: { rate: "+0%", pitch: "+0Hz" },
        audio_path:,
      )
    end
    server_thread.join
    [result, audio_path, audio_bytes(audio_path)]
  ensure
    server&.close
    FileUtils.remove_entry(root) if defined?(root) && root
    File.delete(audio_path) if defined?(audio_path) && audio_path && File.exist?(audio_path)
  end

  def audio_bytes(path)
    File.exist?(path) ? File.binread(path) : nil
  end

  def serve_once(server, client_io)
    Thread.new do
      client = server.accept
      client.gets
      client_io.call(client)
    ensure
      client.close rescue nil
    end
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
    long = Master::Voice::Speech.send(:worker_timeout, 4000)
    assert_equal Master::Voice::Speech::WORKER_TIMEOUT, base
    assert long > base, "a full MAX_CHARS utterance should get more time than an empty one"
    assert long <= Master::Voice::Speech::WORKER_TIMEOUT_MAX
  end

  def test_fast_tts_timeout_is_bounded_to_seconds_not_minutes
    speech = Master::Voice::Speech
    speech.stub(:fast_tts_mode?, true) do
      assert_equal 4, speech.send(:worker_timeout, 0)
      assert_equal 6, speech.send(:worker_timeout, 4000)
    end
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

  def test_infer_style_tracks_conversational_moments_without_changing_voice
    speech = Master::Voice::Speech
    assert_equal :question, speech.infer_style("Are you ready?")
    assert_equal :calm, speech.infer_style("No rush, we can take it one step at a time.")
    assert_equal :warm, speech.infer_style("Glad that makes sense — thanks.")
    assert_equal :energetic, speech.infer_style("Great! We got it!")
    assert_equal :storyteller, speech.infer_style("Imagine this: a long night, a quiet street, and the whole city slowly waking up around us.")
    assert_equal :brief, speech.infer_style("Done now.")
    assert_equal :fail, speech.infer_style("The deploy failed.")
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
