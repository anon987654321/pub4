# frozen_string_literal: true

require "test_helper"

class OmniauthCallbacksControllerTest < ActionDispatch::IntegrationTest
  Info = Struct.new(:email)
  Auth = Struct.new(:provider, :uid, :info, :extra)

  test "only supported providers with an explicit verified email claim prove mailbox ownership" do
    controller = OmniauthCallbacksController.new

    google_verified = auth_for("google_oauth2", email_verified: true)
    google_unverified = auth_for("google_oauth2", email_verified: false)
    vipps_verified = auth_for("vipps", email_verified: true)
    facebook_email = auth_for("facebook", email_verified: true)

    assert controller.send(:verified_provider_email?, google_verified)
    refute controller.send(:verified_provider_email?, google_unverified)
    assert controller.send(:verified_provider_email?, vipps_verified)
    refute controller.send(:verified_provider_email?, facebook_email)
  end

  test "an unverified social email cannot silently attach to an existing account" do
    controller = OmniauthCallbacksController.new
    controller.define_singleton_method(:external_identity_for) { |_auth| nil }
    existing_user = User.new(email_address: "existing@example.test")
    auth = auth_for("facebook", email_verified: true, email: existing_user.email_address)

    User.stub(:find_by, existing_user) do
      assert_raises(OmniauthCallbacksController::IdentityEmailConflict) do
        controller.send(:find_or_create_user, auth)
      end
    end
  end

  test "an identity without an email cannot verify its synthetic placeholder" do
    controller = OmniauthCallbacksController.new
    controller.define_singleton_method(:external_identity_for) { |_auth| nil }
    auth = auth_for("bankid", email_verified: false, email: nil)

    user = controller.send(:find_or_create_user, auth)

    assert user.persisted?
    assert_match(/@bankid\.oauth\z/, user.email_address)
    refute user.email_verified?
  end

  test "a returning BankID subject reuses its unverified legacy placeholder" do
    controller = OmniauthCallbacksController.new
    controller.define_singleton_method(:external_identity_for) { |_auth| nil }
    auth = auth_for("bankid", email_verified: false, email: nil)
    legacy = User.new(email_address: "#{auth.uid}@bankid.oauth", password: SecureRandom.hex(24))
    legacy.require_email_verification = true
    legacy.save!
    original_id = legacy.id

    assert_no_difference -> { User.count } do
      user = controller.send(:find_or_create_user, auth)
      assert_equal original_id, user.id
    end

    identity = ExternalIdentity.joins(:identity_provider)
                               .find_by!(subject: auth.uid, identity_providers: { slug: "bankid" })
    assert_equal original_id, identity.user_id
    refute legacy.reload.email_verified?
  end

  private

  def auth_for(provider, email_verified:, email: "person@example.test")
    Auth.new(
      provider,
      "subject-#{provider}",
      Info.new(email),
      { raw_info: { email_verified: email_verified } }
    )
  end
end
