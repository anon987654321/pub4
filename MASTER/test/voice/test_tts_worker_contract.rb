# frozen_string_literal: true

require_relative "../test_helper"
require "minitest/mock"

class TtsWorkerContractTest < Minitest::Test
  def setup
    @speech_class = Class.new do
      include Master::Voice::SpeechWorker
      def self.name; "TestSpeech"; end
      def warn_tts(msg); end
      def fast_tts_mode?; false; end
    end
    @speech = @speech_class.new
  end

  def test_edge_worker_rejects_nil_process_arguments_before_spawn
    # Missing voice_name
    err = assert_raises(ArgumentError) do
      @speech.run_edge_worker("hello", nil, {rate: "1.0", pitch: "1.0"}, "/tmp/out.mp3", 5)
    end
    assert_includes err.message, "voice"

    # Missing rate
    err = assert_raises(ArgumentError) do
      @speech.run_edge_worker("hello", "en-US-AriaNeural", {rate: nil, pitch: "1.0"}, "/tmp/out.mp3", 5)
    end
    assert_includes err.message, "rate"

    # Missing pitch
    err = assert_raises(ArgumentError) do
      @speech.run_edge_worker("hello", "en-US-AriaNeural", {rate: "1.0", pitch: nil}, "/tmp/out.mp3", 5)
    end
    assert_includes err.message, "pitch"

    # Missing output_path
    err = assert_raises(ArgumentError) do
      @speech.run_edge_worker("hello", "en-US-AriaNeural", {rate: "1.0", pitch: "1.0"}, nil, 5)
    end
    assert_includes err.message, "output_path"
  end

  def test_worker_timeout_respects_env_override
    ENV["MASTER_TTS_TIMEOUT"] = "123"
    assert_equal 123, @speech.worker_timeout(100)
  ensure
    ENV.delete("MASTER_TTS_TIMEOUT")
  end

  def test_worker_timeout_fast_mode_calculates_correctly
    @speech.define_singleton_method(:fast_tts_mode?) { true }
    # 4s base + ceil(100 * 0.01) = 5s, capped at 6s
    assert_equal 5, @speech.worker_timeout(100)
    # 4s base + ceil(300 * 0.01) = 7s, capped at 6s
    assert_equal 6, @speech.worker_timeout(300)
  end

  def test_worker_timeout_normal_mode_uses_speech_constants
    base = Master::Voice::Speech::WORKER_TIMEOUT
    per_char = Master::Voice::Speech::WORKER_TIMEOUT_PER_CHAR
    cap = Master::Voice::Speech::WORKER_TIMEOUT_MAX
    assert_equal base + (100 * per_char).ceil, @speech.worker_timeout(100)
    assert_equal base + (500 * per_char).ceil, @speech.worker_timeout(500)
    assert_equal cap, @speech.worker_timeout(1_000_000)
  end

  def test_stream_timeout_allows_the_audio_duration_in_fast_mode
    ENV.delete("MASTER_TTS_STREAM_TIMEOUT")
    @speech.define_singleton_method(:fast_tts_mode?) { true }

    assert_equal 20, @speech.stream_timeout(100)
    assert_equal 36, @speech.stream_timeout(300)
    assert_equal 90, @speech.stream_timeout(2000)
  ensure
    ENV.delete("MASTER_TTS_STREAM_TIMEOUT")
  end

  def test_stream_timeout_respects_explicit_override
    ENV["MASTER_TTS_STREAM_TIMEOUT"] = "123"

    assert_equal 123, @speech.stream_timeout(300)
  ensure
    ENV.delete("MASTER_TTS_STREAM_TIMEOUT")
  end

  def test_normal_stream_timeout_preserves_the_worker_budget
    @speech.define_singleton_method(:fast_tts_mode?) { false }

    assert_equal @speech.worker_timeout(300), @speech.stream_timeout(300)
  end

  def test_stream_wire_enabled_defaults_to_true
    ENV.delete("MASTER_TTS_WIRE")
    assert @speech.stream_wire_enabled?
  end

  def test_stream_wire_enabled_raw_disables
    ENV["MASTER_TTS_WIRE"] = "raw"
    refute @speech.stream_wire_enabled?
  ensure
    ENV.delete("MASTER_TTS_WIRE")
  end

  def test_missing_replacement_socket_preserves_the_failed_retry_state
    warnings = []
    @speech.define_singleton_method(:warn_tts) { |message| warnings << message }
    @speech.define_singleton_method(:resolve_socket_path) { nil }

    result = @speech.synthesize_edge_socket(
      text: "hello",
      voice_name: "en-US-ChristopherNeural",
      style_config: { rate: "+0%", pitch: "+0Hz" },
      audio_path: "/tmp/unused-empty-socket-test.mp3",
      retried: true,
    )

    assert_nil result
    assert_equal ["edge socket unavailable after worker retry"], warnings
  end

  def test_build_socket_request_produces_valid_json
    req = @speech.build_socket_request("en-US-AriaNeural", {rate: "1.2", pitch: "0.8"}, "hello")
    parsed = JSON.parse(req)
    assert_equal "en-US-AriaNeural", parsed["voice"]
    assert_equal "1.2", parsed["rate"]
    assert_equal "0.8", parsed["pitch"]
    assert_equal "hello", parsed["text"]
    assert_equal true, parsed["stream"]
  end

  def test_cleanup_failed_audio_returns_nil_and_unlinks
    path = "/tmp/test_audio_#{SecureRandom.hex(4)}.mp3"
    File.write(path, "dummy")
    result = @speech.cleanup_failed_audio(path)
    assert_nil result
    refute File.exist?(path)
  end

  def test_cleanup_failed_audio_handles_nil_gracefully
    assert_nil @speech.cleanup_failed_audio(nil)
  end

  def test_read_frame_returns_eof_on_nil_header
    sock = StringIO.new("")
    result = @speech.send(:read_frame, sock, StringIO.new)
    assert_equal :eof, result
  end

  def test_read_frame_returns_clean_on_zero_size
    sock = StringIO.new([0].pack("Q>"))
    result = @speech.send(:read_frame, sock, StringIO.new)
    assert_equal :clean, result
  end

  def test_read_frame_detects_raw_response_when_size_exceeds_max
    # Header with size > FRAME_MAX_S (8 MiB)
    huge = (1 << 23) + 1
    sock = StringIO.new([huge].pack("Q>") + "raw mp3 data")
    sink = StringIO.new
    target = Master::Voice::SpeechWorker::StreamTarget.build(io: sink)
    result = @speech.send(:read_frame, sock, target)
    assert_equal [:raw, 8 + 12], result  # header(8) + body(12)
    # The misread "header" is the first eight bytes of the mp3, so it is forwarded too.
    assert_equal ([huge].pack("Q>") + "raw mp3 data").b, sink.string.b
  end
  def test_daemon_race_probe_accepts_the_versioned_health_reply
    source = File.read(File.join(Master::ROOT, "bin", "tts-worker"), encoding: "UTF-8")

    assert_match(/probe\.gets\.to_s\.strip\.start_with\?\("ok "\)/, source)
    refute_match(/probe\.gets\.to_s\.strip\s*==\s*"ok"/, source)
  end


end
