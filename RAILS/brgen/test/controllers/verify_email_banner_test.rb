# frozen_string_literal: true

require "test_helper"

# An account that may not post until its email is confirmed hears so once,
# up front, instead of meeting require_verified_email when it submits.
class VerifyEmailBannerTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    host! "brgen.no"
  end

  # Created verified, as every test account is; unverified is set after.
  def member(verified:)
    user = User.strict_loading(false).create!(
      email_address: "veb_#{SecureRandom.hex(3)}@brgen.no", password: "password123",
      username: "veb_#{SecureRandom.hex(3)}", guest: false, city: @city
    )
    user.update_columns(email_verified_at: nil) unless verified
    user
  end

  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  test "an unverified account sees the banner once a session, with a resend button" do
    sign_in(member(verified: false))

    get root_path
    assert_select "aside.verify-email-notice p", text: I18n.t("verify.needed")
    assert_select "aside.verify-email-notice form[action=?]", resend_verification_path

    get root_path
    assert_select "aside.verify-email-notice", count: 0
  end

  test "a verified account and a guest see no banner" do
    get root_path
    assert_select "aside.verify-email-notice", count: 0

    sign_in(member(verified: true))
    get root_path
    assert_select "aside.verify-email-notice", count: 0
  end
end
