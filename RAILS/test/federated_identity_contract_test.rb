# frozen_string_literal: true

require "minitest/autorun"

class FederatedIdentityContractTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def read(relative)
    File.read(File.join(ROOT, relative))
  end

  def test_federated_identity_models_have_one_shared_owner
    %w[external_identity.rb identity_provider.rb].each do |name|
      assert File.file?(File.join(ROOT, "RAILS/__shared/app/models", name)), "shared model missing: #{name}"
      refute File.exist?(File.join(ROOT, "RAILS/brgen/app/models", name)),
             "Brgen must not shadow the shared #{name} implementation"
    end
  end

  def test_amber_has_app_owned_migration_for_shared_oauth_callback_tables
    migration = read("RAILS/amber/db/migrate/20261021230100_add_federated_identity_tables_to_amber.rb")
    %w[identity_providers external_identities].each do |table|
      assert_includes migration, "create_table :#{table}, if_not_exists: true"
    end
    assert_includes migration, "index_external_identities_on_provider_and_subject"
    assert_includes migration, "foreign_key: true"
    assert_includes migration, "ActiveRecord::IrreversibleMigration"
    merge_migration = read("RAILS/amber/db/migrate/20261021230200_add_guest_account_merges_to_amber.rb")
    assert_includes merge_migration, "ActiveRecord::IrreversibleMigration"
  end

  def test_email_less_bankid_login_is_looked_up_by_persisted_subject
    callback = read("RAILS/__shared/app/controllers/omniauth_callbacks_controller.rb")
    assert_includes callback, "::ExternalIdentity.find_by(identity_provider_id: provider.id, subject: auth.uid.to_s)"
    assert_includes callback, "def ensure_identity_storage!"
    assert_includes callback, "raise IdentityStorageUnavailable unless available"
    assert_includes callback, 't("shared.flash.oauth_storage_unavailable")'
    assert_includes read("RAILS/__shared/config/locales/social.en.yml"), "oauth_storage_unavailable:"
    assert_includes read("RAILS/__shared/config/locales/social.nb.yml"), "oauth_storage_unavailable:"
    assert_includes read("RAILS/amber/test/controllers/bankid_identity_persistence_test.rb"),
                    "test \"OAuth does not create a duplicate account while federated identity storage is unavailable\""
    assert_includes read("RAILS/amber/test/controllers/bankid_identity_persistence_test.rb"),
                    "test \"lower-assurance BankID cannot reclaim a legacy synthetic account\""
    assert_includes callback, '::IdentityProvider.find_by(slug: auth.provider.to_s)'
    assert_includes callback, "identity.save!"
    assert_includes callback, 'legacy_email = "#{auth.uid}@bankid.oauth"'
    assert_includes callback, "legacy_user.email_verification_token.blank?"
    assert_includes callback, 'raise IdentityEmailConflict unless eligible'
  end

  def test_high_assurance_bankid_write_exception_does_not_mark_email_verified
    auth = read("RAILS/__shared/app/controllers/concerns/shared/authentication.rb")
    callback = read("RAILS/__shared/app/controllers/omniauth_callbacks_controller.rb")
    assert_includes auth, "verified_bankid_identity?(user)"
    assert_includes auth, 'identity_providers: { slug: "bankid" }'
    assert_includes callback, 'when "bankid"'
    assert_includes callback, 'acr.to_s == "urn:bankid:bid" ? "verified" : "account"'
    assert_includes callback, "assurance_level_for(auth.provider, auth:)"
    assert_includes callback, "record.update!("
    assert_includes read("RAILS/amber/test/controllers/bankid_identity_persistence_test.rb"),
                    "test \"persisted BankID assurance follows the current verified token\""
    assert_includes read("RAILS/__shared/lib/omniauth/strategies/bankid.rb"), 'acr_values: "urn:bankid:bid"'
    assert_includes callback, '::ExternalIdentity.find_by(identity_provider_id: provider.id, subject: auth.uid.to_s)'
    assert_includes callback, '::ExternalIdentity.find_or_initialize_by(identity_provider_id: provider.id, subject: auth.uid.to_s)'
    refute_includes callback, "provider&.external_identities"
    assert_includes callback, 'user.require_email_verification = true unless verified_email'
  end

  def test_guest_history_merger_has_one_owner_and_preserves_amber_chat
    merger = read("RAILS/__shared/app/services/account_merger.rb")
    registration = read("RAILS/__shared/app/controllers/concerns/shared/email_registration.rb")
    brgen_controller = read("RAILS/brgen/app/controllers/users_controller.rb")
    amber_controller = read("RAILS/amber/app/controllers/registrations_controller.rb")
    merge_migration = read("RAILS/amber/db/migrate/20261021230200_add_guest_account_merges_to_amber.rb")
    amber_user = read("RAILS/amber/app/models/user.rb")

    refute File.exist?(File.join(ROOT, "RAILS/brgen/app/services/account_merger.rb"))
    refute File.exist?(File.join(ROOT, "RAILS/brgen/app/models/account_merge.rb"))
    assert_includes merger, "def merge_messages"
    assert_includes merger, "def merge_conversations"
    assert_includes merger, "def merge_message_receipts"
    assert_includes merger, "def clear_guest_typing_indicators"
    assert_includes merger, 'model.find_by(conversation_id: source.conversation_id, user_id: user.id)'
    assert_includes merger, 'model.find_by(message_id: source.message_id, user_id: user.id)'
    assert_includes merger, 'values[column] = times.min if times.any?'
    assert_includes merger, "def invalidate_guest_sessions"
    assert_includes merger, '::Session.where(user_id: guest_user.id).find_each(&:destroy!)'
    messenger_test = read("RAILS/brgen/test/services/account_merger_and_moderation_test.rb")
    assert_includes messenger_test, "test \"merging duplicate messenger membership and receipts preserves state without violating unique indexes\""
    assert_includes messenger_test, "assert_equal guest_delivered.to_i, receipt.delivered_at.to_i"
    assert_includes merger, "ActiveRecord::MigrationError"
    refute_includes merger, "guest_user.sessions.destroy_all"
    refute_includes merger, "merge_sessions"
    assert_includes merger, 'columns.include?("sender_id")'
    assert_includes merger, 'columns.include?("recipient_id")'
    assert_includes merger, "def merge_trust_signals"
    assert_includes merger, '::TrustSignal.where(user_id: guest_user.id).update_all(user_id: user.id)'
    assert_includes merger, '::ModerationFlag.where(user_id: guest_user.id).update_all(user_id: user.id)'
    assert_includes merger, "ActiveRecord::MigrationError"
    assert_includes merger, "def record_merge"
    assert_includes merger, "def retire_guest_source"
    assert_includes merger, "deleted_at: Time.current"
    assert_includes merger, 'email_address: "merged-#{guest_user.id}-#{SecureRandom.hex(6)}@deleted.invalid"'
    assert_includes merger, "password_digest: BCrypt::Password.create"
    assert_includes merger, "guest_user.update_columns(attributes)"
    assert_includes read("RAILS/brgen/app/models/user/core_associations.rb"), "has_many :account_merges_as_guest"
    assert_includes amber_user, "has_many :account_merges_as_guest"
    assert_includes registration, "persisted_guest_for_registration"
    assert_includes registration, "transfer_guest_history_to(user, guest)"
    assert_includes brgen_controller, "merge_registration_guest(@user, guest)"
    assert_includes amber_controller, "merge_registration_guest(@user, guest)"
    assert_includes merge_migration, "create_table :account_merges, if_not_exists: true"
    assert_includes amber_user, "has_many :account_merges, dependent: :destroy"
  end

  def test_authentication_paths_refuse_session_rotation_when_history_transfer_fails
    auth = read("RAILS/__shared/app/controllers/concerns/shared/authentication.rb")
    sessions = read("RAILS/__shared/app/controllers/concerns/shared/sessions_actions.rb")
    callback = read("RAILS/__shared/app/controllers/omniauth_callbacks_controller.rb")
    brgen = read("RAILS/brgen/app/controllers/users_controller.rb")
    amber = read("RAILS/amber/app/controllers/registrations_controller.rb")

    assert_includes auth, "def transfer_guest_history_to(user, guest)"
    assert_includes auth, 'AccountMerge.exists?(guest_user_id: guest.id, user_id: user.id, status: "merged")'
    assert_includes auth, "def transfer_guest_history_from_session(user)"
    assert_includes sessions, "transfer_guest_history_from_session(user)"
    assert_includes sessions, 'transfer == false'
    assert_operator sessions.index("transfer_guest_history_from_session(user)"),
                    :<, sessions.index("start_new_session_for user")
    assert_includes callback, 'transfer == false'
    assert_includes callback, 't("shared.flash.guest_history_transfer_failed")'
    assert_includes brgen, 't("shared.email_verification.signup_guest_merge_failed")'
    assert_includes amber, 't("shared.email_verification.signup_guest_merge_failed")'
    assert_includes read("RAILS/__shared/config/locales/social.en.yml"), "guest_history_transfer_failed:"
    assert_includes read("RAILS/__shared/config/locales/social.nb.yml"), "guest_history_transfer_failed:"
    signup_failure = read("RAILS/amber/test/controllers/registrations_controller_test.rb")
    sign_in_failure = read("RAILS/amber/test/controllers/sessions_controller_guest_transfer_test.rb")
    assert_includes signup_failure, "test \"signup leaves guest history and session intact when transfer is blocked\""
    assert_includes signup_failure, "session[:guest_user_id]"
    assert_includes sign_in_failure, "test \"password sign-in preserves the guest session when history transfer fails\""
    assert_includes sign_in_failure, "refute Session.exists?(user_id: member.id)"
  end
end
