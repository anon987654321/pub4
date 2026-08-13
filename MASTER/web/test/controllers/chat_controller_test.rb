# frozen_string_literal: true

require "test_helper"

class ChatControllerTest < ActionDispatch::IntegrationTest
  test "index renders chat shell" do
    get root_path

    assert_response :success
    assert_includes response.body, "launch AI"
    assert_includes response.body, "MASTER_ASSET_PATHS"
    assert_includes response.body, "function loadFace"
    assert_includes response.body, "window.__MASTER_FACE_IMPORT__"
    assert_includes response.body, "window._primerFired"
    assert_includes response.body, "error-live"
    assert_match(%r{/assets/face-[0-9a-f]+\.js}, response.body)
    assert_match(%r{face_state-[0-9a-f]+\.js}, response.body)
    assert_match(%r{visual_bridge-[0-9a-f]+\.js}, response.body)
    assert_match(%r{chat_actions-[0-9a-f]+\.js}, response.body)
    assert_includes response.body, "35000"
    refute_includes response.body, "15000"
    assert_match(/function go\(\)\{[\s\S]*?revealPrompt/, response.body)
    assert_match(/function go\(\)\{[\s\S]*?dismissPrimer/, response.body)
    # TTS/voice settings UI removed — persona defaults only (c3a186a3f, reinforced 2026-07-10).
    refute_includes response.body, "voice-picker"
    refute_includes response.body, "tts-style-chips"
    refute_includes response.body, "tts-style-indicator"
    refute_includes response.body, "face-controls"
    assert_includes response.body, "spin-btn"
    assert_includes response.body, 'data-profile="public"'
    assert_includes response.body, "have a code?"
    assert_includes response.body, "scope-label"
    refute_includes response.body, "operator surface"
  end

  test "authenticated index offers issue not redeem" do
    get root_path, headers: auth_headers

    assert_response :success
    assert_includes response.body, 'data-profile="operator"'
    assert_includes response.body, "issue code"
    refute_includes response.body, "have a code?"
  end

  test "index face asset paths are wired for blob import replacement" do
    get root_path

    assert_response :success
    %w[
      face_semantics face_minimal_ui face_loops_music face_loops_nudge
      face_blendshape_bridge master_events shortcut_sheet particle_worker
    ].each do |name|
      assert_match(/#{Regexp.escape(name)}/, response.body)
    end
    assert_match(/faceRuntime/, response.body)
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

  test "visitor slash stays forbidden except pair redeem" do
    post "/chat/message", params: { message: "/shell ls" }

    assert_response :forbidden
  end

  test "visitor can redeem a pairing code in chat" do
    issued = Master::Ground::Pairing.issue(label: "chat")
    post "/chat/message", params: { message: "/pair #{issued[:code]}" }

    assert_response :success
    assert_includes response.body, "paired"
    assert cookies[:master_paired].present?
  ensure
    FileUtils.rm_rf(File.join(Master::ROOT, ".master", "pairing"))
  end

  test "message accepts seven field felt state" do
    felt = "curious|thinking|0.42|0.88|0.55|0.12|0.35"
    post "/chat/message", params: { message: "ping", state: felt }

    assert_response :success
    assert_includes response.body, "pong"
  end
end
