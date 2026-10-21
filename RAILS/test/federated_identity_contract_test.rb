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
  end

  def test_email_less_bankid_login_is_looked_up_by_persisted_subject
    callback = read("RAILS/__shared/app/controllers/omniauth_callbacks_controller.rb")
    assert_includes callback, "external_identities&.find_by(subject: auth.uid.to_s)"
    assert_includes callback, '::IdentityProvider.find_by(slug: auth.provider.to_s)'
    assert_includes callback, "identity.save!"
    assert_includes callback, 'legacy_email = "#{auth.uid}@bankid.oauth"'
    assert_includes callback, 'raise IdentityEmailConflict unless eligible'
  end

  def test_high_assurance_bankid_write_exception_does_not_mark_email_verified
    auth = read("RAILS/__shared/app/controllers/concerns/shared/authentication.rb")
    callback = read("RAILS/__shared/app/controllers/omniauth_callbacks_controller.rb")
    assert_includes auth, "verified_bankid_identity?(user)"
    assert_includes auth, 'identity_providers: { slug: "bankid" }'
    assert_includes callback, 'when "vipps", "bankid" then "verified"'
    assert_includes callback, 'user.require_email_verification = true unless verified_email'
  end

  def test_guest_history_merger_has_one_owner_and_preserves_amber_chat
    merger = read("RAILS/__shared/app/services/account_merger.rb")
    registration = read("RAILS/__shared/app/controllers/concerns/shared/email_registration.rb")
    controller = read("RAILS/amber/app/controllers/registrations_controller.rb")
    merge_migration = read("RAILS/amber/db/migrate/20261021230200_add_guest_account_merges_to_amber.rb")

    refute File.exist?(File.join(ROOT, "RAILS/brgen/app/services/account_merger.rb"))
    refute File.exist?(File.join(ROOT, "RAILS/brgen/app/models/account_merge.rb"))
    assert_includes merger, "def merge_messages"
    assert_includes merger, 'columns.include?("sender_id")'
    assert_includes merger, 'columns.include?("recipient_id")'
    assert_includes merger, "def merge_trust_signals"
    assert_includes merger, "def record_merge"
    assert_includes registration, "persisted_guest_for_registration"
    assert_includes registration, "AccountMerger.new(guest_user: guest, user: user).call"
    assert_includes controller, "merge_registration_guest(@user, guest)"
    assert_includes merge_migration, "create_table :account_merges, if_not_exists: true"
  end
end
