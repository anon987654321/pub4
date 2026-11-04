# frozen_string_literal: true

require "test_helper"

# The manifest painted the installed app's title bar and splash sky blue
# (#0ea5e9) while the pages, and their meta theme-color, are white.
class ManifestColoursTest < ActionDispatch::IntegrationTest
  test "the manifest colours match the page's theme-color" do
    get root_url
    theme = css_select("meta[name=theme-color]").first["content"]

    get pwa_manifest_path(format: :json)
    assert_response :success
    manifest = JSON.parse(response.body)
    assert_equal theme, manifest["theme_color"]
    assert_equal theme, manifest["background_color"]
  end
end
