# frozen_string_literal: true

require "test_helper"

class BankidIdentityPersistenceTest < ActionDispatch::IntegrationTest
  Info = Struct.new(:email, :phone)
  Auth = Struct.new(:provider, :uid, :info, :extra)

  test "a BankID subject without email reuses the persisted account on later callbacks" do
    uid = "bankid-subject-#{SecureRandom.hex(8)}"
    auth = Auth.new(
      "bankid",
      uid,
      Info.new(nil, nil),
      { id_info: { iss: "https://auth.bankid.no/auth/realms/prod", acr: "urn:bankid:bid" } }
    )
    callback = OmniauthCallbacksController.new
    first = nil

    assert_difference -> { User.count }, 1 do
      first = callback.send(:find_or_create_user, auth)
    end

    provider = IdentityProvider.find_by!(slug: "bankid")
    identity = ExternalIdentity.find_by!(identity_provider: provider, subject: uid)
    assert_equal first.id, identity.user_id
    assert_equal "verified", identity.assurance_level
    assert_nil identity.email_address
    refute first.reload.email_verified?, "a synthetic placeholder must not become email proof"

    second = nil
    assert_no_difference -> { User.count } do
      second = callback.send(:find_or_create_user, auth)
    end
    assert_equal first.id, second.id
  end

  test "a returning BankID subject reclaims its unverified legacy placeholder" do
    uid = "legacy-bankid-#{SecureRandom.hex(8)}"
    legacy = User.new(email_address: "#{uid}@bankid.oauth", password: SecureRandom.hex(24))
    legacy.require_email_verification = true
    legacy.save!
    auth = Auth.new("bankid", uid, Info.new(nil, nil),
                    { id_info: { iss: "https://auth.bankid.no/auth/realms/prod", acr: "urn:bankid:bid" } })
    callback = OmniauthCallbacksController.new

    assert_no_difference -> { User.count } do
      returned = callback.send(:find_or_create_user, auth)
      assert_equal legacy.id, returned.id
    end

    provider = IdentityProvider.find_by!(slug: "bankid")
    identity = ExternalIdentity.find_by!(identity_provider: provider, subject: uid)
    assert_equal legacy.id, identity.user_id
    refute legacy.reload.email_verified?
  end

  test "persisted BankID assurance permits claimed-identity writes without email proof" do
    uid = "bankid-subject-#{SecureRandom.hex(8)}"
    auth = Auth.new(
      "bankid",
      uid,
      Info.new(nil, nil),
      { id_info: { iss: "https://auth.bankid.no/auth/realms/prod", acr: "urn:bankid:bid" } }
    )
    user = OmniauthCallbacksController.new.send(:find_or_create_user, auth)
    controller = ApplicationController.new

    Current.set(user:) do
      assert_nil controller.send(:require_verified_email)
    end
  end

  def test_bankid_identity_without_email_can_create_a_social_post
    uid = "bankid-subject-#{SecureRandom.hex(8)}"
    auth = Auth.new(
      "bankid",
      uid,
      Info.new(nil, nil),
      { id_info: { iss: "https://auth.bankid.no/auth/realms/prod", acr: "urn:bankid:bid" } }
    )
    user = OmniauthCallbacksController.new.send(:find_or_create_user, auth)
    session_record = user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")
    cookies.signed[:session_id] = session_record.id

    refute user.reload.email_verified?, "BankID must not fabricate mailbox verification"
    assert_difference -> { Post.count }, 1 do
      post posts_url, params: { post: { body: "A signed-in BankID member can post without an email claim" } }
    end
    assert_redirected_to posts_url
  end

  test "BankID without the high-assurance ACR cannot bypass email verification" do
    uid = "bankid-low-#{SecureRandom.hex(8)}"
    auth = Auth.new(
      "bankid",
      uid,
      Info.new(nil, nil),
      { id_info: { iss: "https://auth.bankid.no/auth/realms/prod", acr: "urn:bankid:low" } }
    )
    user = OmniauthCallbacksController.new.send(:find_or_create_user, auth)
    provider = IdentityProvider.find_by!(slug: "bankid")
    identity = ExternalIdentity.find_by!(identity_provider_id: provider.id, subject: uid)
    controller = ApplicationController.new

    assert_equal "account", identity.assurance_level
    refute controller.send(:verified_bankid_identity?, user)
    refute user.reload.email_verified?
  end

  test "a non-BankID identity does not inherit the email-verification exception" do
    user = User.new(email_address: "unverified-#{SecureRandom.hex(6)}@example.test",
                    password: SecureRandom.hex(24))
    user.require_email_verification = true
    user.save!

    provider = IdentityProvider.create!(name: "Facebook", slug: "facebook")
    ExternalIdentity.create!(user:, identity_provider: provider, subject: "subject-#{SecureRandom.hex(8)}",
                             assurance_level: "verified")
    controller = ApplicationController.new

    refute controller.send(:verified_bankid_identity?, user)
  end
end
