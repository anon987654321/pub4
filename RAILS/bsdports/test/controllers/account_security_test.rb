# frozen_string_literal: true

require "test_helper"

# bsdports keeps no email verification columns, so a changed address is saved
# and nothing else is asked of it; the password change works as in the others.
class AccountSecurityTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.strict_loading(false).create!(email_address: "konto-#{SecureRandom.hex(4)}@bsdports.test",
                                               password: "password")
    post session_path, params: { email_address: @user.email_address, password: "password" }
  end

  test "the account page renders the security rows" do
    get account_path

    assert_response :success
    assert_select "form[action=?]", email_account_path
    assert_select "form[action=?]", password_account_path
  end

  test "an address change needs the current password and then saves" do
    address = "ny-#{SecureRandom.hex(4)}@bsdports.test"

    patch email_account_path, params: { email_address: address, current_password: "wrong" }
    assert_not_equal address, @user.reload.email_address

    patch email_account_path, params: { email_address: address, current_password: "password" }
    assert_equal address, @user.reload.email_address
  end

  test "a password change keeps this session and ends the others" do
    other = @user.sessions.create!(user_agent: "old laptop")

    patch password_account_path, params: { current_password: "password", password: "new-password-1",
                                           password_confirmation: "new-password-1" }

    assert @user.reload.authenticate("new-password-1")
    assert_not Session.exists?(other.id)
  end
end
