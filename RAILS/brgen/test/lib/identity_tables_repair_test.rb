# frozen_string_literal: true

require "test_helper"

class IdentityTablesRepairTest < ActiveSupport::TestCase
  REPAIR = File.expand_path("../../db/migrate/20260813230000_repair_missing_identity_and_trust_tables.rb", __dir__)
  TABLES = %w[
    identity_providers external_identities identity_assurances
    trust_signals reputation_scores account_merges moderation_flags
  ].freeze

  test "repair migration uses if_not_exists so a healthy schema is a no-op" do
    source = File.read(REPAIR)
    TABLES.each do |table|
      assert_includes source, "create_table :#{table}, if_not_exists: true"
    end
    assert_includes source, "def down"
    assert_includes source, "Do not drop"
  end

  test "the seven identity tables exist in this checkout's schema" do
    TABLES.each do |table|
      assert ActiveRecord::Base.connection.data_source_exists?(table), "#{table} missing from schema"
    end
  end
end
