# frozen_string_literal: true

require "test_helper"

class ChatControllerTest < ActionDispatch::IntegrationTest
  test "index renders chat shell" do
    get root_path

    assert_response :success
    assert_includes response.body, "tap to enter"
    assert_includes response.body, 'id="primer-tier"'
    assert_includes response.body, "visitor"
    assert_includes response.body, 'name="master-mode"'
    assert_includes response.body, 'id="boot-wayfinding"'
    assert_includes response.body, "face_wayfinding"
    assert_includes response.body, "master:face-ready"
    assert_includes response.body, "master:face-stage"
    assert_includes response.body, "master:session-ready"
    assert_includes response.body, "sessionReady"
    assert_includes response.body, "showBootError"
    assert_includes response.body, "ensurePrimer"
    assert_includes response.body, "faceBooting"
    assert_includes response.body, "face-session"
    assert_includes response.body, "face3d_preview"
    assert_includes response.body, "importmap"
    assert_includes response.body, "master-container-ready"
    assert_match(%r{container_gate-[0-9a-f]+\.js}, response.body)
    assert_match(%r{sse_contract-[0-9a-f]+\.js}, response.body)
    assert_match(%r{felt_state-[0-9a-f]+\.js}, response.body)
    assert_includes response.body, "60000"
    refute_includes response.body, "15000"
    assert_match(/function go\(\)\{[\s\S]*?revealPrompt/, response.body)
    assert_match(/function go\(\)\{[\s\S]*?dismissPrimer/, response.body)
    refute_includes response.body, "voice-picker"
    refute_includes response.body, "tts-style-chips"
    refute_includes response.body, "spin-btn"
  end

  test "index face asset paths are wired for blob import replacement" do
    get root_path

    assert_response :success
    %w[
      face_semantics face_minimal_ui face_loops_music face_loops_nudge
      face_blendshape_bridge face3d_preview face3d_geometry face3d_support
      master_events shortcut_sheet particleWorker
    ].each do |name|
      assert_match(/#{Regexp.escape(name)}/, response.body)
    end
    assert_match(/faceParts/, response.body)
    assert_match(/faceModules/, response.body)
    assert_match(/faceRuntime/, response.body)
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

  test "message post streams sse for chat turn" do
    post "/chat/message", params: { message: "ping" }

    assert_response :success
    assert_match %r{text/event-stream}, response.media_type.to_s
    assert_includes response.body, "pong"
    assert_includes response.body, "[DONE]"
  end

  test "message streams warming sse when container absent" do
    Rails.application.config.x.master_container = nil
    Rails.application.config.x.master_bootstrap_started = false

    post "/chat/message", params: { message: "hello" }

    assert_response :success
    assert_match %r{text/event-stream}, response.media_type.to_s
    assert_includes response.body, "booting"
    assert_includes response.body, "[DONE]"
  end

  test "message accepts seven field felt state" do
    felt = "curious|thinking|0.42|0.88|0.55|0.12|0.35"
    post "/chat/message", params: { message: "ping", state: felt }

    assert_response :success
    assert_includes response.body, "pong"
  end
end