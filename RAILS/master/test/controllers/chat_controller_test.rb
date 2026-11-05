# frozen_string_literal: true

require "test_helper"

class ChatControllerTest < ActionDispatch::IntegrationTest
  test "index tells a visitor without JavaScript what is missing" do
    get root_path

    assert_response :success
    noscript = Regexp.escape(I18n.t("face.primer_noscript"))
    assert_match(%r{<noscript><p id="primer-noscript"[^>]*>#{noscript}</p></noscript>}, response.body)
  end

  test "index renders chat shell" do
    get root_path

    assert_response :success
    assert_includes response.body, I18n.t("face.primer_title")
    assert_includes response.body, "MASTER_ASSET_PATHS"
    # The boot script is public/face_primer.js: digested, nonced, synchronous,
    # and handed the digested face.js URL.
    primer_tag = Regexp.new('<script src="/assets/face_primer-[0-9a-f]+\.js" nonce="[^"]+"\s+' \
                            'data-face-module="/assets/face-[0-9a-f]+\.js"></script>')
    assert_match(primer_tag, response.body)
    primer = Rails.root.join("public/face_primer.js").read
    assert_includes primer, "function loadFace"
    assert_includes primer, "window.__MASTER_FACE_IMPORT__"
    assert_includes primer, "window._primerFired"
    assert_includes response.body, "error-live"
    assert_match(%r{/assets/face-[0-9a-f]+\.js}, response.body)
    assert_match(%r{face_state-[0-9a-f]+\.js}, response.body)
    assert_match(%r{visual_bridge-[0-9a-f]+\.js}, response.body)
    assert_match(%r{chat_actions-[0-9a-f]+\.js}, response.body)
    assert_includes primer, "35000"
    refute_includes primer, "15000"
    refute_includes response.body, "15000"
    assert_match(/function go\(\)\{[\s\S]*?revealPrompt/, primer)
    assert_match(/function go\(\)\{[\s\S]*?dismissPrimer/, primer)
    # TTS/voice settings UI removed — persona defaults only (c3a186a3f, reinforced 2026-07-10).
    refute_includes response.body, "voice-picker"
    refute_includes response.body, "tts-style-chips"
    refute_includes response.body, "tts-style-indicator"
    refute_includes response.body, "face-controls"
    assert_includes response.body, "pause-speech-button"
    assert_includes response.body, 'data-profile="public"'
    # #scope-row — the scope word, the pairing form and its hint — came off the
    # corners on operator request (10fabb8ae). The page must not grow it back.
    refute_includes response.body, "scope-label"
    refute_includes response.body, "have a code?"
    refute_includes response.body, "operator surface"
    assert_includes response.body, 'lang="nb"'
    # /runtime/config is fetched after the tap; preloading it would pay for it
    # on every visit that never taps.
    refute_match(%r{<link[^>]*preload[^>]*runtime/config}, response.body)
  end

  test "index is English when the browser asks" do
    get root_path, headers: { "HTTP_ACCEPT_LANGUAGE" => "en-GB,en;q=0.9" }

    assert_response :success
    assert_includes response.body, 'lang="en"'
    assert_includes response.body, I18n.with_locale(:en) { I18n.t("face.primer_title") }
  end

  # The visible pairing panel is gone; pairing is not. Redeeming still works
  # through PairControllerTest and through `/pair <code>` in the prompt
  # (test_visitor_can_redeem_a_pairing_code_in_chat below), so what is left to
  # assert here is the profile mark — it is what decides which tools the face
  # will run, and it is the half that survived the panel.
  test "index marks the profile for a visitor and for an operator" do
    get root_path
    assert_response :success
    assert_includes response.body, 'data-profile="public"'

    get root_path, headers: auth_headers
    assert_response :success
    assert_includes response.body, 'data-profile="operator"'
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

    post "/chat/message", params: { message: "ping" }

    assert_response :success
    assert_match %r{text/event-stream}, response.media_type.to_s
    assert_includes response.body, "pong"
    assert_includes response.body, "[DONE]"
  end

  test "message rejects empty input" do
    post "/chat/message", params: { message: "" }

    assert_response :bad_request
  end

  # A chat turn spends model budget, so it is not reachable by a GET a link,
  # prefetch or crawler can make.
  test "message does not answer GET" do
    get "/chat/message", params: { message: "hello" }

    assert_response :not_found
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

  test "index names this host, links through the routes and uses native landmarks" do
    host! "face.example.test"
    get root_path, env: { "SCRIPT_NAME" => "/master" }

    assert_response :success
    assert_select ".brand-mark .brand-text", text: "face.example.test"
    assert_select "a.brand-mark[href='/master/']"
    assert_select "a.master-session-tab[href='/master/'][aria-current='page']"
    assert_select "a.master-session-tab[href='/master/dashboard']"
    assert_select "main#chat-shell:not([role])"
  end

  test "index uses the icon file as its favicon and lets the photo picker offer the gallery" do
    get root_path

    assert_select "link[rel='icon'][type='image/svg+xml'][href*='/assets/icon-']"
    refute_match(%r{rel="icon"[^>]*data:}, response.body)
    assert_select "input#photo[type='file'][accept='image/*']"
    assert_select "input#photo[capture]", count: 0
  end

  test "index names the service worker cache after the deployed revision, not a fixed v2" do
    revision = ENV["CACHE_VERSION"].presence || Rails.application.config.x.booted_sha || "dev"
    get root_path

    assert_includes response.body, %(window.MASTER_CACHE_VERSION = #{revision.to_json};)
    refute_includes response.body, %(window.MASTER_CACHE_VERSION = "v2";)
  end
end
