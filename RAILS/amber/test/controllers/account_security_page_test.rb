# frozen_string_literal: true

require "test_helper"

# amber renders the shared account page's security rows: email, password and
# the devices signed in, and signs the other devices out.
class AccountSecurityPageTest < ActionDispatch::IntegrationTest
  test "the account page offers email, password and device rows, and signs out the others" do
    user = User.strict_loading(false).create!(email_address: "sikker-amber-#{SecureRandom.hex(3)}@example.com",
                                              password: "password")
    user.sessions.create!(user_agent: "Gammel mobil")
    post session_path, params: { email_address: user.email_address, password: "password" }

    get account_path
    assert_select "form[action=?]", email_account_path
    assert_select "form[action=?]", password_account_path
    assert_select ".account-sessions li", 2

    delete other_sessions_account_path
    assert_equal 1, user.sessions.count
  end
end
