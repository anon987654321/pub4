# frozen_string_literal: true

require "test_helper"

# The footer's home link carries aria-label, and the logo inside it was an
# img with its own label and <title>, so screen readers announced the name
# two or three times.
class FooterLogoTest < ActionDispatch::IntegrationTest
  test "the footer logo is hidden inside its labelled link" do
    get root_path
    assert_response :success
    assert_select "a.amber-footer-home[aria-label] svg[aria-hidden=true]", 1
    assert_select "a.amber-footer-home svg[role=img]", 0
    assert_select "a.amber-footer-home svg title", 0
  end
end
