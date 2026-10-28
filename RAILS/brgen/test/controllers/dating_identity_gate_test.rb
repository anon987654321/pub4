# frozen_string_literal: true

require "test_helper"

# The identity gate on Dating::BaseController is the one thing standing between
# a signed-in account and the right to appear in front of strangers. These
# tests pin its two axioms: a configured Vipps admits only vipps_verified
# accounts, and an unconfigured Vipps closes the gate unless the operator has
# named the demo bypass — never an open door by accident of missing env.
class DatingIdentityGateTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @user = User.strict_loading(false).create!(
      email_address: "gate@brgen.no", password: "password123",
      username: "gate", guest: false, city: @city
    )
    @previous_slugs = Rails.application.config.x.oauth_provider_slugs
    @previous_bypass = ENV["DATING_IDENTITY_BYPASS"]
  end

  teardown do
    ActsAsTenant.current_tenant = nil
    Rails.application.config.x.oauth_provider_slugs = @previous_slugs
    if @previous_bypass.nil?
      ENV.delete("DATING_IDENTITY_BYPASS")
    else
      ENV["DATING_IDENTITY_BYPASS"] = @previous_bypass
    end
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
    host! "dating.brgen.no"
  end

  def with_vipps(available)
    Rails.application.config.x.oauth_provider_slugs = available ? %w[vipps] : []
  end

  test "without Vipps configured the profile form stays locked" do
    with_vipps(available: false)
    ENV.delete("DATING_IDENTITY_BYPASS")
    sign_in_as(@user)

    get dating.new_profile_path

    assert_redirected_to sign_in_path
    assert flash[:alert].present?
  end

  test "the demo bypass opens the locked gate because the operator named it" do
    with_vipps(available: false)
    ENV["DATING_IDENTITY_BYPASS"] = "demo"
    sign_in_as(@user)

    get dating.new_profile_path

    assert_response :success
  end

  test "an unknown bypass value opens nothing" do
    with_vipps(available: false)
    ENV["DATING_IDENTITY_BYPASS"] = "1"
    sign_in_as(@user)

    get dating.new_profile_path

    assert_redirected_to sign_in_path
  end

  test "with Vipps configured the gate answers to verification, not the bypass" do
    with_vipps(available: true)
    ENV["DATING_IDENTITY_BYPASS"] = "demo"
    sign_in_as(@user)

    get dating.new_profile_path

    assert_redirected_to sign_in_path
  end
end
