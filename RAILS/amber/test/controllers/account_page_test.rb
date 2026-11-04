# frozen_string_literal: true

require "test_helper"

# The account page is brgen's and amber's shared view; brgen adds rows through
# an app partial amber does not have, and the page renders without it.
class AccountPageTest < ActionDispatch::IntegrationTest
  test "the account page renders its own rows without an app partial" do
    user = User.strict_loading(false).create!(email_address: "konto-amber@example.com", password: "password")
    post session_path, params: { email_address: user.email_address, password: "password" }

    get account_path

    assert_response :success
    assert_select ".account-settings a[href=?]", export_account_path
  end
end
