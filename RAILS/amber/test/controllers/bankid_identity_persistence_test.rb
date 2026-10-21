# frozen_string_literal: true

require "test_helper"

class BankidIdentityPersistenceTest < ActiveSupport::TestCase
  Info = Struct.new(:email, :phone)
  Auth = Struct.new(:provider, :uid, :info, :extra)

  test "a BankID subject without email reuses the persisted account on later callbacks" do
    uid = "bankid-subject-#{SecureRandom.hex(8)}"
    auth = Auth.new(
      "bankid",
      uid,
      Info.new(nil, nil),
      { id_info: { iss: "https://auth.bankid.no/auth/realms/prod" } }
    )
    callback = OmniauthCallbacksController.new
    first = nil

    assert_difference -> { User.count }, 1 do
      first = callback.send(:find_or_create_user, auth)
    end

    identity = ExternalIdentity.joins(:identity_provider)
                               .find_by!(subject: uid, identity_providers: { slug: "bankid" })
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

  test "persisted BankID assurance permits claimed-identity writes without email proof" do
    uid = "bankid-subject-#{SecureRandom.hex(8)}"
    auth = Auth.new(
      "bankid",
      uid,
      Info.new(nil, nil),
      { id_info: { iss: "https://auth.bankid.no/auth/realms/prod" } }
    )
    user = OmniauthCallbacksController.new.send(:find_or_create_user, auth)
    controller = ApplicationController.new

    Current.set(user:) do
      assert_nil controller.send(:require_verified_email)
    end
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
