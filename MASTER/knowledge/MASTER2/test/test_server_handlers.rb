# frozen_string_literal: true

require_relative "test_helper"
require "stringio"

class TestServerHandlers < Minitest::Test
  def setup
    @server = MASTER::Server.allocate
  end

  def test_tts_stream_requires_text
    status, headers, body = @server.handle_tts_stream({ "QUERY_STRING" => "" })

    assert_equal 400, status
    assert_equal "application/json", headers["content-type"]
    assert_equal '{"error":"no text provided"}', body.join
  end

  def test_tts_stream_returns_audio_when_speech_succeeds
    MASTER::Speech.stub :speak, MASTER::Result.ok(audio: "FAKEAUDIO") do
      status, headers, body = @server.handle_tts_stream({ "QUERY_STRING" => "text=hello" })

      assert_equal 200, status
      assert_equal "audio/mpeg", headers["content-type"]
      assert_equal "FAKEAUDIO", body.join
    end
  end

  def test_tts_stream_returns_json_error_when_speech_returns_empty_audio
    MASTER::Speech.stub :speak, MASTER::Result.ok({}) do
      status, headers, body = @server.handle_tts_stream({ "QUERY_STRING" => "text=hello" })

      assert_equal 500, status
      assert_equal "application/json", headers["content-type"]
      assert_equal '{"error":"TTS returned empty audio"}', body.join
    end
  end

  def test_tts_stream_returns_json_error_when_speech_fails
    MASTER::Speech.stub :speak, MASTER::Result.err("speech backend down") do
      status, headers, body = @server.handle_tts_stream({ "QUERY_STRING" => "text=hello" })

      assert_equal 500, status
      assert_equal "application/json", headers["content-type"]
      assert_equal({ "error" => "speech backend down" }, JSON.parse(body.join))
    end
  end

  def test_tts_post_uses_same_success_contract
    env = { "rack.input" => StringIO.new('{"text":"hello"}') }

    MASTER::Speech.stub :speak, MASTER::Result.ok(data: "BINAUDIO") do
      status, headers, body = @server.handle_tts(env)

      assert_equal 200, status
      assert_equal "audio/mpeg", headers["content-type"]
      assert_equal "BINAUDIO", body.join
    end
  end
end
