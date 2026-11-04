# frozen_string_literal: true

require "test_helper"

# The layout preloaded /icon.png as an image, but no page body renders the
# icon; the tab icon is fetched by the browser on its own, so the preload
# only competed with the stylesheet.
class LayoutHeadTest < ActionDispatch::IntegrationTest
  test "the icon is linked but not preloaded" do
    get root_url
    assert_response :success
    assert_select "head link[rel=icon][href='/icon.png']", 1
    assert_select "head link[rel=preload][href='/icon.png']", 0
  end
end
