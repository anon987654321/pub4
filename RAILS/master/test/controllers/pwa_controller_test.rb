# frozen_string_literal: true

require "test_helper"

# sw.js precaches /manifest.json and the shell links pwa_manifest_path(format:
# :json); both reach this route only because no static file shadows it.
class PwaControllerTest < ActionDispatch::IntegrationTest
  test "the manifest the service worker precaches answers as installable JSON" do
    get "/manifest.json"

    assert_response :success
    assert_equal "application/json", response.media_type
    body = JSON.parse(response.body)
    assert_equal "/", body["start_url"]
    assert_equal "fullscreen", body["display"]
    assert_includes body["display_override"], "fullscreen"
    assert body["icons"].any? { |icon| icon["sizes"] == "512x512" }
    face_bg = Master.tokens.fetch("face_root").fetch("face_bg")
    assert_equal face_bg, body["theme_color"]
    assert_equal face_bg, body["background_color"]
  end

  test "the manifest is served to a visitor without a token" do
    get "/manifest.json"

    assert_response :success
    assert_nil response.headers["Location"]
  end

  test "the manifest speaks the visitor's language and says it depends on it" do
    get "/manifest.json"
    nb = JSON.parse(response.body)
    assert_equal I18n.t("pwa.description", locale: :nb), nb["description"]
    assert_equal "nb", nb["lang"]
    assert_includes response.headers["Vary"].to_s, "Accept-Language"

    get "/manifest.json", headers: { "HTTP_ACCEPT_LANGUAGE" => "en-GB,en;q=0.9" }
    en = JSON.parse(response.body)
    assert_equal "Public MASTER chat", en["description"]
    assert_equal [ "Chat", "Focus face", "Mission control" ], en["shortcuts"].pluck("name")
    refute_equal en["shortcuts"].pluck("description"), nb["shortcuts"].pluck("description")
  end

  # sw.js serves this page when the network is gone; it is MASTER's, not brgen's.
  test "the offline page names MASTER in the face's own ink" do
    get "/offline.html"

    assert_response :success
    assert_select "title", text: "MASTER — frakoblet"
    assert_select "main h1", text: "MASTER"
    refute_match(/brgen/i, response.body)
    refute_includes response.body, "#f5f0e8"
  end
end
