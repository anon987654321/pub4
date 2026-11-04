# frozen_string_literal: true

require "test_helper"

# The wardrobe's lifecycle filter marked the chosen chip with a
# chip--active class that no stylesheet defines, so neither sighted nor
# screen-reader users could tell which filter was on.
class LifecycleChipCurrentTest < ActionDispatch::IntegrationTest
  test "the chosen lifecycle chip is aria-current and styled" do
    email = "lc-#{SecureRandom.hex(4)}@example.test"
    User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: email, password: "password" }

    get items_path(lifecycle: "repair")
    assert_response :success
    assert_select "nav.chips a.chip[aria-current=page][href=?]", items_path(lifecycle: "repair")
    assert_select ".chip--active", 0
    stylesheet = Rails.root.join("app/assets/stylesheets/application.scss").read
    assert_includes stylesheet, %(.chip[aria-current="page"] {)
  end
end
