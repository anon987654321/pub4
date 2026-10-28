# frozen_string_literal: true

require_relative "../test_helper"
require "socket"
require "tmpdir"

class TestSpeech < Minitest::Test
  # These tests exercise synthesis plumbing, not the machine's daemon pool. A
  # real ensure_daemon! spawns tts-worker processes and waits for their sockets,
  # so a checkout with no daemon running hung every test that reached it.
  def setup
    @supervisor = Master::Voice::TtsSupervisor.singleton_class
    @supervisor.send(:alias_method, :real_ensure_daemon!, :ensure_daemon!)
    @supervisor.send(:define_method, :ensure_daemon!) { |**| true }
  end

  def teardown
    @supervisor.send(:alias_method, :ensure_daemon!, :real_ensure_daemon!)
    @supervisor.send(:remove_method, :real_ensure_daemon!)
  end

  # Expressive synthesis still has its own shaping contract; normal speech
  # defaults to the direct path so alternate engines cannot change the words.
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

  def test_transcendent_success_does_not_depend_on_quality_log_file
    transcendent = Master::Voice::Transcendent
    Dir.mktmpdir("master_tts_quality_log") do |dir|
      output = File.join(dir, "speech.mp3")
      File.binwrite(output, "synthetic audio bytes")

      transcendent.stub(:build_engine_chain, ["edge"]) do
        transcendent.stub(:try_engine_chain, [true, :edge]) do
          transcendent.stub(:log_pick, nil) do
            transcendent.stub(:log_quality, nil) do
              assert_equal true, transcendent.synthesize_via_chain(
                "Hello.", {}, {}, {}, :christopher, "+0%", "+0Hz", output
              )
            end
          end
        end
      end
    end
  end

  def test_a_tts_failure_prints_once_and_stays_in_last_error
    speech = Master::Voice::Speech
    message = "probe failure #{Process.pid}"
    out, err = capture_io { 3.times { speech.send(:warn_tts, message) } }

    assert_equal 1, (out + err).lines.grep(/#{message}/).size
    assert_equal message, speech.instance_variable_get(:@last_error)
  end

  def test_tts_timing_is_always_available_and_detailed_logs_are_opt_in
    speech = Master::Voice::Speech
    original = ENV.fetch("MASTER_TTS_TIMING", nil)
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) - 0.01

    ENV.delete("MASTER_TTS_TIMING")
    output, = capture_io { speech.log_timing("probe", started_at, text_length: 4) }
    assert_empty output
    assert_operator speech.last_timings.fetch("probe").fetch(:elapsed_ms), :>=, 0

    ENV["MASTER_TTS_TIMING"] = "1"
    output, err = capture_io { speech.log_timing("probe", started_at, text_length: 4) }
    assert_match(/timing stage=probe elapsed_ms=\d+ chars=4/, output + err)
    assert_operator speech.last_timings.fetch("probe").fetch(:chars), :==, 4
  ensure
    original ? ENV["MASTER_TTS_TIMING"] = original : ENV.delete("MASTER_TTS_TIMING")
  end

  # Entrypoint has already made the parent's bundle MASTER's own, so the daemon
  # inherits that context; only the Gemfile is pinned to the daemon's root.
  def test_daemon_env_carries_the_prepared_bundle_and_pins_the_gemfile
    vars = { "BUNDLE_PATH" => "/prepared/bundle", "BUNDLE_GEMFILE" => "/wrong/web/Gemfile", "GEM_HOME" => "/prepared/gems" }
    with_env(vars) do
      Dir.mktmpdir("master_tts_env") do |root|
        env = Master::Voice::TtsSupervisor.daemon_env(root)
        assert_equal "/prepared/bundle", env["BUNDLE_PATH"]
        assert_equal "/prepared/gems", env["GEM_HOME"]
        assert_equal File.join(root, "Gemfile"), env["BUNDLE_GEMFILE"]
        assert_equal ENV.fetch("HOME", ""), env["HOME"]
      end
    end
  end

  # Regression: confirmed live on vm23 -- Falcon's own process has RUBYLIB
  # pointing at web's vendored bundler-4.0.7/lib and BUNDLE_LOCKFILE pointing
  # at web/Gemfile.lock. Neither was in BUNDLE_ISOLATION_KEYS, so tts-worker
  # daemons resolved web's lockfile against MASTER's Gemfile and crashed with
  # Bundler::GemNotFound on every single spawn.
  def test_daemon_env_strips_rubylib_and_bundle_lockfile_pollution
    vars = { "RUBYLIB" => "/wrong/web/vendor/bundle/ruby/3.4/gems/bundler-4.0.7/lib", "BUNDLE_LOCKFILE" => "/wrong/web/Gemfile.lock" }
    with_env(vars) do
      Dir.mktmpdir("master_tts_env") do |root|
        env = Master::Voice::TtsSupervisor.daemon_env(root)
        assert_nil env["RUBYLIB"]
        assert_nil env["BUNDLE_LOCKFILE"]
      end
    end
  end

  # The assertions above read the hash, but Process.spawn merges the hash onto
  # the parent's environment: an absent key is inherited, only a key named with
  # nil is unset. Falcon's bundle-exec variables reached the worker that way.
  def test_daemon_env_names_the_parents_bundler_keys_with_nil_so_spawn_unsets_them
    env = Master::Voice::TtsSupervisor.daemon_env(Master::ROOT)
    %w[RUBYOPT RUBYLIB BUNDLE_LOCKFILE BUNDLE_BIN_PATH BUNDLER_SETUP BUNDLER_VERSION BUNDLE_DEPLOYMENT].each do |key|
      assert env.key?(key), "#{key} must be named so Process.spawn unsets the inherited value"
      assert_nil env[key]
    end
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
        client.write("ok #{Master::Voice::TtsSupervisor.worker_version(Master::ROOT)}\n")
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
    source = File.read(File.expand_path("../../lib/voice/playback.rb", __dir__))
    assert_includes source, "ProcessSpawn.options"
    source = File.read(File.expand_path("../../lib/voice/tts_supervisor.rb", __dir__))
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

  def test_explicit_classic_mode_can_be_overridden_per_session
    speech = Master::Voice::Speech
    original = ENV["MASTER_TTS_MODE"]
    ENV.delete("MASTER_TTS_MODE")

    Master::Voice::Transcendent.stub(:load_config, { "fast_mode" => true, "default_mode" => "classic", "enabled" => true }) do
      assert_equal "classic", speech.synthesis_mode
      ENV["MASTER_TTS_MODE"] = "transcendent"
      assert_equal "transcendent", speech.synthesis_mode
      ENV["MASTER_TTS_MODE"] = "classic"
      assert_equal "classic", speech.synthesis_mode
    end
  ensure
    original ? ENV["MASTER_TTS_MODE"] = original : ENV.delete("MASTER_TTS_MODE")
  end

  def test_transcendent_streaming_is_opt_in
    original = ENV["MASTER_TTS_MODE"]
    ENV.delete("MASTER_TTS_MODE")

    Master::Voice::Transcendent.stub(:load_config, { "fast_mode" => true, "default_mode" => "classic", "enabled" => true }) do
      assert_equal false, Master::Voice::Speech.send(:transcendent_streaming_enabled?, {})
      ENV["MASTER_TTS_MODE"] = "transcendent"
      assert_equal true, Master::Voice::Speech.send(:transcendent_streaming_enabled?, {})
    end
  ensure
    original ? ENV["MASTER_TTS_MODE"] = original : ENV.delete("MASTER_TTS_MODE")
  end

  def test_default_tts_config_keeps_live_streaming_fast_and_cli_speech_literal
    original = ENV["MASTER_TTS_MODE"]
    ENV.delete("MASTER_TTS_MODE")
    cfg = Master::Voice::Transcendent.load_config
    assert_equal true, cfg.fetch("enabled")
    assert_equal true, cfg.fetch("fast_mode")
    assert_equal "classic", cfg.fetch("default_mode")

    # On macOS, the declared default keeps spoken words literal. OpenBSD keeps
    # its existing host-specific policy unless the operator changes it.
    Master::Voice::Engines.stub(:openbsd?, false) do
      assert_equal "classic", Master::Voice::Speech.synthesis_mode
    end
  ensure
    original ? ENV["MASTER_TTS_MODE"] = original : ENV.delete("MASTER_TTS_MODE")
  end

  def without_tts_mode_pin
    pinned = ENV.delete("MASTER_TTS_MODE")
    yield
  ensure
    ENV["MASTER_TTS_MODE"] = pinned if pinned
  end

  def test_fast_mode_does_not_override_cli_synthesis_or_live_streaming_contract
    without_tts_mode_pin { fast_mode_contract }
  end

  def fast_mode_contract
    config = { "fast_mode" => true, "default_mode" => "transcendent", "enabled" => true }
    Master::Voice::Transcendent.stub(:load_config, config) do
      speech = Master::Voice::Speech
      assert_equal "transcendent", speech.synthesis_mode
      assert_equal true, speech.fast_tts_mode?
      assert_equal false, speech.send(:transcendent_streaming_enabled?, {})
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

  def test_playback_tracks_player_without_recursive_lock_and_checks_exit_status
    playback = Master::Voice::Playback
    status = Struct.new(:success?).new(true)
    Dir.mktmpdir("master-playback-lock") do |dir|
      path = File.join(dir, "answer.mp3")
      File.write(path, "fake-audio")
      generation = playback.current_generation
      playback.stub(:player_candidates, [["fake-player", []]]) do
        Master::Device::Audio.stub(:media_player_available?, false) do
          Process.stub(:spawn, ->(*_args, **_options) { 987_654 }) do
            Process.stub(:wait2, ->(pid) { [pid, status] }) do
              assert playback.play(path, generation:)
            end
          end
        end
      end
      assert_nil playback.instance_variable_get(:@playing_pid)
    end
  end

  def test_native_audio_mime_types
    assert_equal "audio/mpeg", Master::Voice::Speech.mime_type_for("a.mp3")
    assert_equal "audio/wav", Master::Voice::Speech.mime_type_for("a.wav")
    assert_equal "audio/mp4", Master::Voice::Speech.mime_type_for("a.m4a")
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
    assert_equal :christopher, Master::Voice::Speech.voice_for_text("The system is ready.")
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

  # Several Speech stubs at one nesting level, for the opt-in OS voice fallback tests.
  def stub_speech(stubs, &block)
    stubs.reduce(block) { |inner, (name, value)| -> { Master::Voice::Speech.stub(name, value) { inner.call } } }.call
  end

  def test_synthesize_falls_back_to_espeak_when_edge_returns_nil
    stub_speech(os_voice_fallback?: true, edge_tts_available?: true, synthesize_edge: nil,
                espeak_path: "/usr/local/bin/espeak", synthesize_espeak: "/tmp/fallback.wav") do
      assert_equal "/tmp/fallback.wav", Master::Voice::Speech.synthesize("hello")
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

  def test_recursive_streaming_synthesis_refuses_cleanly_when_pool_is_full
    speech = Master::Voice::Speech
    nested_results = []
    nested_errors = []
    unlocked = lambda do |text, output_path:, _on_chunk: nil, **_opts|
      if text == "outer"
        nested_results << Fiber.new { speech.synthesize_streaming_to_file("nested", output_path:) }.resume
        nested_errors << speech.last_error
        "outer-result"
      else
        flunk "nested synthesis must be refused before reaching the locked worker slot"
      end
    end

    Master::Voice::TtsSupervisor.stub(:pool_size, 1) do
      speech.stub(:synthesize_streaming_to_file_unlocked, unlocked) do
        assert_equal "outer-result", speech.synthesize_streaming_to_file(
          "outer", output_path: File.join(Dir.tmpdir, "unused-recursive-test.mp3"),
        )
      end
    end

    assert_equal [false], nested_results
    assert_match(/recursive streaming synthesis refused/, nested_errors.fetch(0))
    assert_nil speech.last_error, "the successful outer synthesis clears nested failure state"
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
    stub_speech(os_voice_fallback?: true, try_transcendent_synthesis: [false, nil], available?: true,
                edge_tts_available?: false, espeak_path: nil, synthesize_say: "/tmp/say-fallback.mp3") do
      assert_equal "/tmp/say-fallback.mp3", Master::Voice::Speech.synthesize("hello")
    end
  end

  def test_synthesize_edge_socket_treats_eof_as_success
    wire = ->(client) { client.write("fake-mp3-bytes") }
    result, _path, bytes = with_edge_stub_server(wire)
    assert bytes, "a whole-file legacy answer must resolve to an audio path"
    assert_equal "fake-mp3-bytes", bytes
  end

  def test_synthesize_edge_socket_retries_once_after_a_truncated_first_response
    calls = 0
    wire = lambda do |client|
      calls += 1
      if calls == 1
        client.write([5].pack("Q>"))
        client.write("bad")
      else
        client.write([5].pack("Q>"))
        client.write("valid")
        client.write([0].pack("Q>"))
      end
    end

    result, _path, bytes = with_edge_stub_server(wire)

    assert result
    assert_equal "valid", bytes
    assert_equal 2, calls, "a socket request gets one retry, not a retry per caller layer"
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
      Master::Voice::TtsSupervisor.stub(:retire_socket, nil) do
        Master::Voice::Speech.synthesize_edge_socket(
          text: "hello",
          voice_name: "en-GB-RyanNeural",
          style_config: { rate: "+0%", pitch: "+0Hz" },
          audio_path:,
        )
      end
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

  # An empty answer retires the worker and asks once more, so the stub serves a
  # second connection when one arrives and stops when none does.
  def serve_once(server, client_io)
    Thread.new do
      2.times do |turn|
        break if turn.positive? && !IO.select([server], nil, nil, 0.5)

        client = server.accept
        begin
          client.gets
          client_io.call(client)
        ensure
          client.close rescue nil
        end
      end
    end
  end

  def test_socket_retry_budget_is_not_restarted_by_the_streaming_caller
    calls = 0
    speech = Master::Voice::Speech
    speech.stub(:synthesize_edge_socket, ->(**) { calls += 1; nil }) do
      refute speech.send(
        :attempt_socket_synthesis,
        "hello",
        "en-GB-RyanNeural",
        { rate: "+0%", pitch: "+0Hz" },
        File.join(Dir.tmpdir, "unused-tts-budget.mp3"),
        nil,
      )
    end

    assert_equal 1, calls
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

  def test_classic_speech_retries_once_after_empty_socket_audio_in_fast_mode
    speech = Master::Voice::Speech
    original_error = speech.last_error
    seen = nil
    audio_path = nil
    synth = lambda do |text:, voice_name:, style_config:, audio_path:, timeout: nil|
      seen = [text, voice_name, style_config, timeout]
      File.binwrite(audio_path, "edge-audio")
      audio_path
    end
    failed_socket = lambda do |**|
      speech.instance_variable_set(:@last_error, "edge socket produced empty audio")
      nil
    end

    speech.stub(:fast_tts_mode?, true) do
      speech.stub(:synthesis_mode, "classic") do
        speech.stub(:normal_worker_timeout, 45) do
          speech.stub(:synthesize_edge_socket, failed_socket) do
            speech.stub(:synthesize_edge_oneshot, synth) do
              result = speech.synthesize_edge(
                "Read these words exactly.",
                voice: :christopher,
                style_config: { rate: "+0%", pitch: "+0Hz" },
                shape: false,
              )
              audio_path = result
              assert_equal "edge-audio", File.binread(result)
            end
          end
        end
      end
    end

    assert_equal "Read these words exactly.", seen.fetch(0)
    assert_equal "en-US-ChristopherNeural", seen.fetch(1)
    assert_equal "+0%", seen.fetch(2).fetch(:rate)
    assert_equal 30, seen.fetch(3)
    assert_nil speech.last_error, "successful Edge retry must clear the recovered socket error"
  ensure
    File.delete(audio_path) if audio_path && File.exist?(audio_path)
    speech.instance_variable_set(:@last_error, original_error) if speech
  end

  def test_fast_classic_speech_does_not_cold_start_when_no_socket_exists
    speech = Master::Voice::Speech
    original_error = speech.last_error
    speech.clear_last_error!

    speech.stub(:fast_tts_mode?, true) do
      speech.stub(:synthesis_mode, "classic") do
        speech.stub(:synthesize_edge_socket, nil) do
          speech.stub(:synthesize_edge_oneshot, ->(**) { flunk "missing socket must not spawn a cold worker" }) do
            assert_nil speech.synthesize_edge(
              "Read these words exactly.",
              voice: :christopher,
              style_config: { rate: "+0%", pitch: "+0Hz" },
              shape: false,
            )
          end
        end
      end
    end
  ensure
    speech.instance_variable_set(:@last_error, original_error) if speech
  end

  def test_synthesize_edge_warns_and_cleans_up_failed_worker_output
    status = Struct.new(:success?).new(false)
    capture_io do
      # Normal mode always permits the bounded one-shot worker; assert that
      # its failed output is removed before the caller falls back.
      Master::Voice::Speech.stub(:fast_tts_mode?, false) do
        Master::Voice::Speech.stub(:synthesize_edge_socket, nil) do
          Master::Io::Exec.stub(:capture3, ["", "worker failed #{Process.pid}", status]) do
            assert_nil Master::Voice::Speech.synthesize_edge(
              "hello",
              voice: :ryan,
              style_config: { rate: "+0%", pitch: "+0Hz" },
            )
          end
        end
      end
    end

    # warn_tts keeps every failure in last_error even when the terminal is quiet.
    assert_includes Master::Voice::Speech.instance_variable_get(:@last_error), "edge worker failed: worker failed #{Process.pid}"
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
    Master::Voice::Speech.stub(:fast_tts_mode?, false) do
      base = Master::Voice::Speech.send(:worker_timeout, 0)
      long = Master::Voice::Speech.send(:worker_timeout, 4000)
      assert_equal Master::Voice::Speech::WORKER_TIMEOUT, base
      assert long > base, "a 4000-character utterance should get more time than an empty one"
      assert long <= Master::Voice::Speech::WORKER_TIMEOUT_MAX
    end
  end

  def test_fast_tts_timeout_is_bounded_to_seconds_not_minutes
    speech = Master::Voice::Speech
    speech.stub(:fast_tts_mode?, true) do
      assert_equal 4, speech.send(:worker_timeout, 0)
      assert_equal 6, speech.send(:worker_timeout, 4000)
    end
  end

  def test_worker_timeout_respects_explicit_env_override_regardless_of_length
    with_env("MASTER_TTS_TIMEOUT" => "7") do
      assert_equal 7, Master::Voice::Speech.send(:worker_timeout, 4000)
    end
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
    assert_equal :energetic, speech.infer_style("We shipped it! Look at that go!")
    assert_equal :storyteller, speech.infer_style("Imagine this: a long night, a quiet street, and the whole city slowly waking up around us.")
    assert_equal :brief, speech.infer_style("Done now.")
    assert_equal :fail, speech.infer_style("The deploy failed.")
  end

  # An opening hedge is padding; "will" carries tense and stays
  # (StrunkPass::MEANING_BEARING_HEDGES).
  def test_clean_text_strips_hedge_words
    result = Master::Voice::Speech.clean_text("I believe this will improve performance.")
    refute_includes result, "I believe"
    assert_includes result, "will improve"
  end

  def test_clean_text_preserves_newline_to_period_pacing
    result = Master::Voice::Speech.clean_text("First line no period\nSecond line no period")
    assert_equal "First line no period. Second line no period", result
  end

  def with_env(vars)
    saved = vars.keys.to_h { |key| [key, ENV[key]] }
    vars.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def with_profile(name)
    saved = ENV.fetch("MASTER_TTS_PROFILE", nil)
    name ? ENV["MASTER_TTS_PROFILE"] = name : ENV.delete("MASTER_TTS_PROFILE")
    Master::Voice::Policy.reload!
    yield
  ensure
    saved ? ENV["MASTER_TTS_PROFILE"] = saved : ENV.delete("MASTER_TTS_PROFILE")
    Master::Voice::Policy.reload!
  end

  def declared_tts = Master.load_yaml(File.join(Master::ROOT, "data", "voice.yml")).fetch("tts")
  def declared_rate = declared_tts["default_rate"]

  def test_no_profile_leaves_the_voice_exactly_as_declared
    with_profile(nil) do
      assert_equal "", Master::Voice::Policy.profile_name
      assert_equal declared_rate, Master::Voice::Policy.default_rate
      assert_empty Master::Voice::Policy.layers
      refute Master::Voice::Layers.active?
      refute Master::Voice::Policy.fx_enabled?
      # The room is whatever tts.room declares; the operator opened it on 2026-10-27.
      declared_room = declared_tts["room"]
      assert_equal declared_room["enabled"] ? declared_room : {}, Master::Voice::Policy.room
    end
  end

  def test_the_dilla_profile_restores_the_effects_and_room
    with_profile("dilla") do
      policy = Master::Voice::Policy
      assert policy.fx_enabled?
      refute_empty policy.room
      chain = policy.shaped_chain
      assert chain.start_with?(policy.post_chain)
      %w[pan=stereo adelay= aecho=].each { |filter| assert_includes chain, filter }
      assert_equal policy.room, policy.browser_payload.fetch(:room)
      assert_equal policy.post_chain, policy.browser_payload.fetch(:post_chain)
      assert policy.room.dig("pan", "follow_head")
    end
  end

  def test_the_dry_profile_restores_the_voice_without_a_room
    with_env("MASTER_TTS_CHARACTER" => "none") do
      with_profile("dry") do
        assert_empty Master::Voice::Policy.room
        assert_equal Master::Voice::Policy.post_chain, Master::Voice::Policy.shaped_chain
      end
    end
  end

  def test_asmr_keeps_its_own_layers_and_no_room
    with_profile("asmr") do
      assert_empty Master::Voice::Policy.room
      assert Master::Voice::Layers.active?
    end
  end

  def test_the_room_holds_loudness_within_one_lu_of_the_dry_voice
    skip "ffmpeg missing" unless system("ffmpeg", "-version", out: File::NULL, err: File::NULL)

    Dir.mktmpdir("room") do |dir|
      # Real speech, not tones: the limiter and compressor in the chain treat a
      # steady tone nothing like a sentence. macOS `say` is the one speaker to hand.
      skip "say missing" unless system("say", "-v", "?", out: File::NULL, err: File::NULL)

      spoken = File.join(dir, "speech.aiff")
      assert system("say", "-o", spoken, "The check passed on all four trees. Nothing was skipped, and the room is ready to hear.")
      source = File.join(dir, "speech.wav")
      assert system("ffmpeg", "-y", "-loglevel", "error", "-i", spoken, "-ac", "1", "-ar", "24000", source)
      loudness = lambda do |chain|
        out = IO.popen(["ffmpeg", "-hide_banner", "-nostats", "-i", source, "-af", "#{chain},ebur128",
                        "-f", "null", "-"], err: %i[child out], &:read)
        out.scan(/I:\s+(-?[\d.]+) LUFS/).last.first.to_f
      end
      # The room alone, which is what this holds to the dry voice; the dilla rack
      # is measured in test_dilla_fx.rb.
      with_env("MASTER_TTS_FX" => "0", "MASTER_TTS_CHARACTER" => "none") do
        with_profile("dilla") do
          wet = loudness.call(Master::Voice::Policy.shaped_chain)
          dry = loudness.call(Master::Voice::Policy.post_chain)
          assert_in_delta dry, wet, 1.0
        end
      end
    end
  end

  def test_the_asmr_profile_overlays_rate_pitch_chain_and_layers
    with_profile("asmr") do
      policy = Master::Voice::Policy
      assert_equal "asmr", policy.profile_name
      assert_equal "-11%", policy.default_rate
      assert_equal "-18Hz", policy.default_pitch
      assert_includes policy.post_chain, "deesser"
      assert Master::Voice::Layers.active?
      assert_equal "asmr", policy.browser_payload.fetch(:profile)
    end
  end

  def test_an_unknown_profile_speaks_the_default_voice
    with_profile("no-such-profile") do
      assert_equal declared_rate, Master::Voice::Policy.default_rate
      refute Master::Voice::Layers.active?
    end
  end

  def test_layers_build_one_seeded_graph_with_a_whisper_bed_and_a_breath_in
    with_profile("asmr") do
      argv = Master::Voice::Layers.command(input: "in.mp3", output: "out.mp3", chain: "anull", seconds: 4.0)
      graph = argv[argv.index("-filter_complex") + 1]
      %w[amerge amultiply concat adelay apad].each { |filter| assert_includes graph, filter }
      assert_equal 3, argv.count("lavfi"), "two whisper channels and one breath"
      assert_equal 3, argv.count { |part| part.include?("seed=") }
      assert_equal ["-map", "[out]", "-ac", "2", "out.mp3"], argv.last(5)
    end
  end

  def test_a_layered_voice_is_never_streamed_piecemeal
    with_profile("asmr") do
      refute Master::Voice::Playback.stream_playback_ready?
    end
  end

  def test_layers_add_a_breath_and_a_pause_and_keep_the_whisper_inside_the_speech
    skip "ffmpeg missing" unless system("ffmpeg", "-version", out: File::NULL, err: File::NULL)

    Dir.mktmpdir("layers") do |dir|
      source = File.join(dir, "speech.mp3")
      burst = "(0.3*sin(2*PI*140*t)+0.1*sin(2*PI*2800*t))*(lt(t,1.2)+gt(t,1.7)*lt(t,3.2))"
      assert system("ffmpeg", "-y", "-loglevel", "error", "-f", "lavfi", "-i",
                    "aevalsrc=exprs='#{burst}':s=24000:d=4", "-ac", "1", source)
      layered = File.join(dir, "layered.mp3")
      with_profile("asmr") { assert Master::Voice::Layers.apply(source, layered) }

      probe = IO.popen(["ffprobe", "-v", "error", "-show_entries", "stream=channels", "-show_entries",
                        "format=duration", "-of", "csv=p=0", layered], &:read).split
      assert_equal 2, probe.first.to_i
      assert_in_delta 4.0 + 0.32 + 0.38, probe.last.to_f, 0.05

      # The gap between the two bursts sits 0.38 s later in the layered file.
      gap = IO.popen(["ffmpeg", "-hide_banner", "-nostats", "-i", layered, "-af",
                      "atrim=start=1.7:duration=0.2,astats=metadata=0:reset=0", "-f", "null", "-"],
                     err: %i[child out], &:read)
      assert_match(/RMS level dB:\s*(-inf|-[1-9]\d\d)/, gap, "the whisper must be silent where the speech is")
    end
  end
end
