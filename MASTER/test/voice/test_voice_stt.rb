# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"
require_relative "../../lib/voice/stt"

class TestVoiceStt < Minitest::Test
  def setup
    @stt = Master::Voice::Stt.build(config: { backend: :null })
  end

  def test_build_null
    assert_equal :null, @stt.backend_name
    refute @stt.available?
  end

  def test_finish_without_start_is_empty
    result = @stt.finish
    assert_equal "", result.text
    refute result.partial?
  end

  def test_utterance_cycle_null
    @stt.start_utterance
    assert @stt.snapshot[:open]
    partial = @stt.feed(Array.new(480, 0.1))
    assert_nil partial
    result = @stt.finish
    assert_equal "", result.text
    assert_equal :null, result.backend
    refute @stt.snapshot[:open]
  end

  def test_reset_closes
    @stt.start_utterance
    @stt.feed(Array.new(100, 0.0))
    @stt.reset!
    refute @stt.snapshot[:open]
    assert_equal 0, @stt.snapshot[:buffered_samples]
  end

  def test_pcm16_accepted
    @stt.start_utterance
    @stt.feed(Array.new(480, 1000))
    result = @stt.finish
    assert_kind_of Master::Voice::Stt::Result, result
  end

  def test_whisper_binary_resolution_uses_the_shared_pathext_lookup
    Dir.mktmpdir("whisper-path") do |dir|
      binary = File.join(dir, "whisper-cli.EXE")
      File.write(binary, "#!/bin/sh\n")
      File.chmod(0o755, binary)
      original_path = ENV["PATH"]
      original_pathext = ENV["PATHEXT"]
      original_binary = ENV["MASTER_WHISPER_BINARY"]
      begin
        ENV["PATH"] = dir
        ENV["PATHEXT"] = ".EXE;.CMD"
        ENV.delete("MASTER_WHISPER_BINARY")
        assert_equal binary, Master::Voice::Stt::WhisperCppBackend.binary_path({})
      ensure
        original_path.nil? ? ENV.delete("PATH") : ENV["PATH"] = original_path
        original_pathext.nil? ? ENV.delete("PATHEXT") : ENV["PATHEXT"] = original_pathext
        original_binary.nil? ? ENV.delete("MASTER_WHISPER_BINARY") : ENV["MASTER_WHISPER_BINARY"] = original_binary
      end
    end
  end

  def test_whisper_cli_capture_preserves_text_and_diagnostics
    with_whisper_binary("echo 'recognized words'; echo 'notice' >&2") do |binary|
      backend = whisper_backend(binary, timeout: 2)
      text, raw = backend.send(:run_whisper, "unused.wav")

      assert_equal "recognized words", text
      assert_equal "recognized words\n", raw[:stdout]
      assert_equal "notice\n", raw[:stderr]
      assert_equal 0, raw[:status]
    end
  end

  def test_whisper_cli_timeout_kills_a_hung_process_promptly
    with_whisper_binary("exec sleep 10") do |binary|
      backend = whisper_backend(binary, timeout: 0.1)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      text, raw = backend.send(:run_whisper, "unused.wav")
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      assert_equal "", text
      assert_match(/timed out/, raw.fetch(:error))
      assert_operator elapsed, :<, 3
    end
  end

  def test_snapshot_frozen
    assert @stt.snapshot.frozen?
  end

  private

  def whisper_backend(binary, timeout:)
    Master::Voice::Stt::WhisperCppBackend.new(
      binary:, model: "unused-model.bin", config: { whisper_timeout_s: timeout }
    )
  end

  def with_whisper_binary(body)
    Dir.mktmpdir("whisper-cpp-test") do |dir|
      binary = File.join(dir, "whisper-cli")
      File.write(binary, "#!/bin/sh\n#{body}\n")
      File.chmod(0o755, binary)
      yield binary
    end
  end
end
