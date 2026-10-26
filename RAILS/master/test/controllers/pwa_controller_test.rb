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
end
