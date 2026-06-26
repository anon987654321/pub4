# frozen_string_literal: true

require "test_helper"

class ChatControllerTest < ActionDispatch::IntegrationTest
  test "index renders chat shell" do
    get root_path

    assert_response :success
    assert_includes response.body, "tap to start"
    assert_includes response.body, "master:face-ready"
    assert_includes response.body, "finishBoot"
    assert_includes response.body, "dismissPrimer"
    assert_includes response.body, "60000"
    refute_includes response.body, "15000"
    refute_includes response.body, "touchstart\",go"
    refute_includes response.body, "voice-picker"
    refute_includes response.body, "tts-style-chips"
    refute_includes response.body, "spin-btn"
  end

  test "index face asset paths are wired for blob import replacement" do
    get root_path

    assert_response :success
    %w[
      face_semantics.js face_minimal_ui.js face_loops_music.js face_loops_nudge.js
      face_blendshape_bridge.js face3d_preview.js
    ].each do |name|
      assert_includes response.body, name
    end
    assert_match(/faceParts:\s*\[/, response.body)
    assert_match(/faceModules:\s*\{/, response.body)
  end

  test "message smoke ping streams sse without container" do
    Rails.application.config.x.master_container = nil

    get "/chat/message", params: { message: "ping" }

    assert_response :success
    assert_match %r{text/event-stream}, response.media_type.to_s
    assert_includes response.body, "pong"
    assert_includes response.body, "[DONE]"
  end

  test "message rejects empty input" do
    get "/chat/message", params: { message: "" }

    assert_response :bad_request
  end
end