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

  def png_size(path)
    get path
    assert_response :success, path
    header = response.body.byteslice(16, 8)
    header.unpack("NN").join("x")
  end

  test "the manifest has an id, one purpose per icon and each PNG at the size it declares" do
    get "/manifest.json"
    body = JSON.parse(response.body)

    assert_equal "/", body["id"]
    pngs = body["icons"].select { |icon| icon["type"] == "image/png" }
    assert_equal %w[192x192 512x512], pngs.pluck("sizes").uniq.sort
    pngs.each do |icon|
      refute_includes icon["purpose"].to_s, " ", "one purpose per entry: #{icon.inspect}"
      assert_equal icon["sizes"], png_size(icon["src"]), icon["src"]
    end
    %w[192x192 512x512].each do |size|
      assert_equal %w[any maskable], pngs.select { |icon| icon["sizes"] == size }.pluck("purpose").sort
    end
  end

  test "the manifest shows a wide and a narrow screenshot at the size each declares" do
    get "/manifest.json"
    shots = JSON.parse(response.body).fetch("screenshots")

    assert_equal %w[narrow wide], shots.pluck("form_factor").sort
    shots.each do |shot|
      refute_empty shot["label"].to_s
      assert_equal shot["sizes"], png_size(shot["src"]), shot["src"]
    end
  end
end
