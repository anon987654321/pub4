# frozen_string_literal: true

require "test_helper"

# The home page titled itself "Dashboard" for everyone, the signed-in
# label, so guests and search results saw a dashboard they cannot open.
class HomeTitleTest < ActionDispatch::IntegrationTest
  test "a guest gets the page's own title, a member the dashboard" do
    get root_path
    assert_response :success
    assert_select "title", text: /\A#{Regexp.escape(I18n.t("home.looks.title"))}/
    assert_select "title", text: /#{I18n.t("home.dashboard")}/, count: 0

    email = "ht-#{SecureRandom.hex(4)}@example.test"
    User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: email, password: "password" }
    get root_path
    assert_select "title", text: /\A#{I18n.t("home.dashboard")}/
  end
end
