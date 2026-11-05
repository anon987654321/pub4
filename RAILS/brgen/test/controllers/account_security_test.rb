# frozen_string_literal: true

require "test_helper"

# The account page changes the sign-in email and password, each behind the
# current password, and signs out the other devices.
class AccountSecurityTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    host! "brgen.no"
    @user = User.strict_loading(false).create!(email_address: "konto-#{SecureRandom.hex(4)}@brgen.no",
                                               password: "password123", city: @city)
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def sign_in
    post session_path, params: { email_address: @user.email_address, password: "password123" }
  end

  test "the account page lists signed-in devices and the email and password forms" do
    @user.sessions.create!(user_agent: "Firefox på jobben", ip_address: "10.0.0.2")
    sign_in

    get account_path

    assert_select "form[action=?]", email_account_path
    assert_select "form[action=?]", password_account_path
    assert_select ".account-sessions li", 2
    assert_includes response.body, "Firefox på jobben"
    assert_select "form[action=?]", other_sessions_account_path
  end

  test "a wrong current password changes nothing" do
    sign_in

    patch email_account_path, params: { email_address: "ny@brgen.no", current_password: "feil" }
    patch password_account_path, params: { current_password: "feil", password: "nytt-passord",
                                           password_confirmation: "nytt-passord" }

    assert_equal I18n.t("account_security.wrong_password"), flash[:alert]
    assert_not_equal "ny@brgen.no", @user.reload.email_address
    assert @user.authenticate("password123")
  end

  test "a new email address is saved and has to be confirmed again" do
    sign_in
    address = "ny-#{SecureRandom.hex(4)}@brgen.no"

    assert_enqueued_emails 1 do
      patch email_account_path, params: { email_address: address, current_password: "password123" }
    end

    @user.reload
    assert_equal address, @user.email_address
    assert_nil @user.email_verified_at
    assert @user.email_verification_token.present?
  end

  test "a new password signs out every other device and keeps this one" do
    other = @user.sessions.create!(user_agent: "Gammel telefon")
    sign_in

    patch password_account_path, params: { current_password: "password123", password: "nytt-passord-1",
                                           password_confirmation: "nytt-passord-1" }

    assert_redirected_to account_path
    assert @user.reload.authenticate("nytt-passord-1")
    assert_not Session.exists?(other.id)
    assert_equal 1, @user.sessions.count
  end

  test "sign out other devices keeps only the current session" do
    @user.sessions.create!(user_agent: "Nettbrett")
    @user.sessions.create!(user_agent: "Laptop")
    sign_in

    delete other_sessions_account_path

    assert_equal 1, @user.sessions.count
    assert_equal I18n.t("account_security.signed_out_others", count: 2), flash[:notice]
  end
end
