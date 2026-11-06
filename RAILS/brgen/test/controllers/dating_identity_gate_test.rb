# frozen_string_literal: true

require "test_helper"

# The identity gate on Dating::BaseController is the one thing standing between
# a signed-in account and the right to appear in front of strangers. These
# tests pin its two axioms: a configured verifier (Vipps or BankID) admits only
# accounts with a verified identity, and an unconfigured Vipps closes the gate unless the operator has
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

  def with_vipps(available:)
    Rails.application.config.x.oauth_provider_slugs = available ? %w[vipps] : []
  end

  test "without Vipps configured the profile form stays locked" do
    with_vipps(available: false)
    ENV.delete("DATING_IDENTITY_BYPASS")
    sign_in_as(@user)

    get dating.new_profile_path

    assert_redirected_to new_session_path
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

    assert_redirected_to new_session_path
  end

  test "with Vipps configured the gate answers to verification, not the bypass" do
    with_vipps(available: true)
    ENV["DATING_IDENTITY_BYPASS"] = "demo"
    sign_in_as(@user)

    get dating.new_profile_path

    assert_redirected_to new_session_path
  end
  def verify(user, slug:, assurance: "verified")
    provider = IdentityProvider.find_or_create_by!(slug:) { |row| row.name = slug.capitalize }
    ExternalIdentity.create!(user:, identity_provider: provider, subject: "sub-#{slug}", assurance_level: assurance)
  end

  test "a BankID identity at LOA 4 opens the gate where BankID is the verifier" do
    Rails.application.config.x.oauth_provider_slugs = %w[bankid]
    verify(@user, slug: "bankid")
    sign_in_as(@user)

    get dating.new_profile_path

    assert_response :success
  end

  test "a BankID login below LOA 4 does not" do
    Rails.application.config.x.oauth_provider_slugs = %w[bankid]
    verify(@user, slug: "bankid", assurance: "account")
    sign_in_as(@user)

    get dating.new_profile_path

    assert_redirected_to new_session_path
  end

  # The first screen names the check the gate really makes, and none when
  # there is none, so it never claims a protection the server does not run.
  test "the first visit opens on the splash, naming the configured verifier" do
    Rails.application.config.x.oauth_provider_slugs = %w[vipps bankid]
    host! "dating.brgen.no"

    get dating.root_path

    assert_response :success
    assert_select ".dating-splash-trust strong", "BankID"
    assert_select "a.dating-splash-start[href=?]", dating.root_path(start: 1)
  end

  test "without a verifier the splash claims no protection" do
    with_vipps(available: false)
    host! "dating.brgen.no"

    get dating.root_path

    assert_select ".dating-splash-trust", count: 0
  end

  test "starting remembers it, so the next visit is the deck" do
    host! "dating.brgen.no"

    get dating.root_path(start: 1)
    assert_redirected_to dating.root_path

    get dating.root_path
    assert_select ".dating-splash", count: 0
  end
end
