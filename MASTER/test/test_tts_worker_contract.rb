# frozen_string_literal: true

require "test_helper"
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
    # Speech::WORKER_TIMEOUT = 8, WORKER_TIMEOUT_PER_CHAR = 0.02, WORKER_TIMEOUT_MAX = 30
    # 8 + ceil(100 * 0.02) = 10
    assert_equal 10, @speech.worker_timeout(100)
    # 8 + ceil(500 * 0.02) = 18
    assert_equal 18, @speech.worker_timeout(500)
    # capped at 30
    assert_equal 30, @speech.worker_timeout(2000)
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
    result = @speech.send(:read_frame, sock, sink)
    assert_equal [:raw, 8 + 12], result  # header(8) + body(12)
    assert_equal "raw mp3 data", sink.string
  end
end
