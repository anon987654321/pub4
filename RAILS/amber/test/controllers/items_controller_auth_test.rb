# frozen_string_literal: true

require "test_helper"

class ItemsControllerAuthTest < ActionDispatch::IntegrationTest
  test "new item redirects visitors without a session" do
    get new_item_path

    assert_redirected_to new_session_path
  end

  test "new item loads after sign in" do
    user = User.strict_loading(false).create!(email_address: "wardrobe@example.com", password: "password")
    post session_path, params: { email_address: user.email_address, password: "password" }

    get new_item_path

    assert_response :success
  end
end