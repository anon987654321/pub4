# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class OmniauthCallbacksControllerTest < ActionDispatch::IntegrationTest
  Info = Struct.new(:email, :phone)
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

  test "a retry reuses its unverified synthetic placeholder when a provider omits email" do
    controller = OmniauthCallbacksController.new
    controller.define_singleton_method(:external_identity_for) { |_auth| nil }
    auth = auth_for("google_oauth2", email_verified: false, email: nil)
    legacy = User.new(
      email_address: controller.send(:synthetic_oauth_address, auth),
      password: SecureRandom.hex(24)
    )
    legacy.require_email_verification = true
    legacy.save!
    original_id = legacy.id

    assert_no_difference -> { User.count } do
      user = controller.send(:find_or_create_user, auth)
      assert_equal original_id, user.id
    end

    refute legacy.reload.email_verified?
    identity = ExternalIdentity.joins(:identity_provider)
                               .find_by!(subject: auth.uid, identity_providers: { slug: "google_oauth2" })
    assert_equal original_id, identity.user_id
  end

  test "a concurrent synthetic placeholder insert is recovered after uniqueness rejection" do
    controller = OmniauthCallbacksController.new
    controller.define_singleton_method(:external_identity_for) { |_auth| nil }
    auth = auth_for("google_oauth2", email_verified: false, email: nil)
    # Saved the way the controller's own candidate is, as the concurrent
    # callback that won the insert would have saved it.
    legacy = User.new(
      email_address: controller.send(:synthetic_oauth_address, auth),
      password: SecureRandom.hex(24)
    )
    legacy.require_email_verification = true
    legacy.save!
    lookup_count = 0
    finder = ->(*) { lookup_count += 1; lookup_count == 1 ? nil : legacy }

    User.stub(:find_by, finder) do
      assert_no_difference -> { User.count } do
        user = controller.send(:find_or_create_user, auth)
        assert_equal legacy.id, user.id
      end
    end
  end

  test "a concurrent provider registry insert is recovered after uniqueness rejection" do
    controller = OmniauthCallbacksController.new
    controller.define_singleton_method(:external_identity_for) { |_auth| nil }
    auth = auth_for("google_oauth2", email_verified: true, email: "person@example.test")
    provider = IdentityProvider.create!(name: "Google OAuth2", slug: "google_oauth2")
    lookup_count = 0
    finder = ->(*) { lookup_count += 1; lookup_count == 1 ? nil : provider }

    IdentityProvider.stub(:find_by, finder) do
      controller.send(:find_or_create_user, auth)
    end

    identity = ExternalIdentity.joins(:identity_provider)
                               .find_by!(subject: auth.uid, identity_providers: { slug: "google_oauth2" })
    assert_equal provider.id, identity.identity_provider_id
  end

  test "email-less OAuth cannot reclaim a guest account sharing the synthetic address" do
    controller = OmniauthCallbacksController.new
    controller.define_singleton_method(:external_identity_for) { |_auth| nil }
    auth = auth_for("google_oauth2", email_verified: false, email: nil)
    guest = User.create!(
      email_address: controller.send(:synthetic_oauth_address, auth),
      password: SecureRandom.hex(24),
      guest: true
    )

    assert_raises(OmniauthCallbacksController::IdentityEmailConflict) do
      controller.send(:find_or_create_user, auth)
    end
    refute ExternalIdentity.joins(:identity_provider)
                           .where(user_id: guest.id, identity_providers: { slug: "google_oauth2" }).exists?
  end

  test "a returning BankID subject reuses its unverified legacy placeholder" do
    controller = OmniauthCallbacksController.new
    controller.define_singleton_method(:external_identity_for) { |_auth| nil }
    # Only a high-assurance login (LOA=4) may reclaim the legacy placeholder.
    auth = auth_for("bankid", email_verified: false, email: nil, acr: "urn:bankid:bid;LOA=4")
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

  test "BankID cannot claim a manually registered unverified placeholder address" do
    controller = OmniauthCallbacksController.new
    controller.define_singleton_method(:external_identity_for) { |_auth| nil }
    auth = auth_for("bankid", email_verified: false, email: nil)
    legacy = User.new(email_address: "#{auth.uid}@bankid.oauth", password: SecureRandom.hex(24))
    legacy.require_email_verification = true
    legacy.save!
    legacy.generate_email_verification!
    token = legacy.reload.email_verification_token

    assert_raises(OmniauthCallbacksController::IdentityEmailConflict) do
      controller.send(:find_or_create_user, auth)
    end

    assert_equal token, legacy.reload.email_verification_token
    refute ExternalIdentity.joins(:identity_provider)
                           .where(user_id: legacy.id, identity_providers: { slug: "bankid" }).exists?
  end

  private

  def auth_for(provider, email_verified:, email: "person@example.test", acr: nil)
    extra = { raw_info: { email_verified: } }
    extra[:id_info] = { acr: } if acr
    Auth.new(provider, "subject-#{provider}", Info.new(email), extra)
  end
end
