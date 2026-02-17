# frozen_string_literal: true

require_relative "test_helper"

class TestWebUiTemplate < Minitest::Test
  TEMPLATE = File.expand_path("../lib/views/cli.html", __dir__)

  def test_template_exists
    assert File.exist?(TEMPLATE), "Expected web UI template at #{TEMPLATE}"
  end

  def test_chat_and_poll_hooks_present
    html = File.read(TEMPLATE)
    assert_includes html, "fetch(\"/chat\""
    assert_includes html, "fetch(\"/poll\""
    assert_includes html, "window.MASTER_TOKEN||''"
  end

  def test_local_first_tts_with_remote_fallback_present
    html = File.read(TEMPLATE)
    assert_includes html, "TTS_BACKEND_KEY"
    assert_includes html, "localTtsAvailable"
    assert_includes html, "speakLocal"
    assert_includes html, "speakRemote"
    assert_includes html, "fetch(\"/tts\""
  end

  def test_voice_input_controls_present
    html = File.read(TEMPLATE)
    assert_includes html, "id=\"mic\""
    assert_includes html, "SpeechRecognition"
    assert_includes html, "webkitSpeechRecognition"
  end
end
