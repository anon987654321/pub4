# frozen_string_literal: true

require_relative "test_helper"

class TestWebTtsContract < Minitest::Test
  WEB_ROOT = File.join(Master::ROOT, "web")

  def test_routes_expose_tts_endpoints
    routes = File.read(File.join(WEB_ROOT, "config", "routes.rb"))
    %w[chat/tts chat/tts/phrases chat/tts/status chat/tts/stream].each do |path|
      assert_includes routes, path, "missing route #{path}"
    end
  end

  def test_tts_controller_sets_viseme_headers
    source = File.read(File.join(WEB_ROOT, "app", "controllers", "tts_controller.rb"))
    assert_includes source, "X-TTS-Visemes"
    assert_includes source, "X-TTS-Job"
    assert_includes source, "Expression.for_pre_speech"
  end

  def test_face_tts_bridge_present
    bridge = File.join(WEB_ROOT, "public", "face_tts_bridge.js")
    assert File.file?(bridge)
    source = File.read(bridge)
    assert_includes source, "tts:"
  end
end