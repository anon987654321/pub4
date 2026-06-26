# frozen_string_literal: true

require "test_helper"

class ChatControllerTest < ActionDispatch::IntegrationTest
  test "index renders chat shell" do
    get root_path

    assert_response :success
    assert_includes response.body, "tap to start"
    assert_includes response.body, "master:face-ready"
    assert_includes response.body, "master:face-stage"
    assert_includes response.body, "showBootError"
    assert_includes response.body, "faceBooting"
    assert_includes response.body, "importmap"
    assert_includes response.body, "60000"
    refute_includes response.body, "15000"
    refute_match(/function go\(\)\{[\s\S]*?dismissPrimer/, response.body)
    refute_includes response.body, "voice-picker"
    refute_includes response.body, "tts-style-chips"
    refute_includes response.body, "spin-btn"
  end

  test "index face asset paths are wired for blob import replacement" do
    get root_path

    assert_response :success
    %w[
      face_semantics.js face_minimal_ui.js face_loops_music.js face_loops_nudge.js
      face_blendshape_bridge.js face3d_preview.js face3d_geometry.js face3d_support.js
      master_events.js shortcut_sheet.js
    ].each do |name|
      assert_includes response.body, name
    end
    assert_match(/faceParts/, response.body)
    assert_match(/faceModules/, response.body)
    assert_match(%r{/assets/face-[0-9a-f]+\.js}, response.body)
  end

  test "index referenced assets resolve via propshaft" do
    get root_path
    assert_response :success

    urls = response.body.scan(%r{/assets/[^"'\s<>]+}).uniq
    refute_empty urls
    urls.first(25).each do |path|
      get path
      assert_response :success, "expected 200 for #{path}, got #{response.status}"
    end
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