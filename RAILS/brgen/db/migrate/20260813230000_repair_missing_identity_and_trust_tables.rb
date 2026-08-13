# frozen_string_literal: true

# 20260514120000 is in schema_migrations on production and created nothing.
# User#destroy, PruneGuestUsersJob, ModerationWorkflow#penalize_owner and
# OAuth all raise StatementInvalid against the missing tables. if_not_exists
# so a healthy schema (this checkout) is a no-op.
class RepairMissingIdentityAndTrustTables < ActiveRecord::Migration[8.0]
  def up
    create_table :identity_providers, if_not_exists: true do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :issuer
      t.string :client_id
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :identity_providers, :slug, unique: true, if_not_exists: true

    create_table :external_identities, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: true
      t.references :identity_provider, null: false, foreign_key: true
      t.string :subject, null: false
      t.string :email_address
      t.string :phone_number
      t.string :assurance_level, null: false, default: "account"
      t.datetime :last_used_at
      t.timestamps
    end
    add_index :external_identities, %i[identity_provider_id subject], unique: true,
                                                                      name: "index_external_identities_on_provider_and_subject",
                                                                      if_not_exists: true

    create_table :identity_assurances, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: true
      t.string :level, null: false
      t.string :source, null: false
      t.datetime :verified_at
      t.datetime :expires_at
      t.timestamps
    end
    add_index :identity_assurances, %i[user_id level], unique: true, if_not_exists: true

    create_table :trust_signals, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :source
      t.integer :weight, null: false, default: 0
      t.text :metadata
      t.timestamps
    end
    add_index :trust_signals, %i[user_id kind], if_not_exists: true

    create_table :reputation_scores, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: true
      t.string :scope, null: false, default: "global"
      t.integer :score, null: false, default: 0
      t.datetime :calculated_at
      t.timestamps
    end
    add_index :reputation_scores, %i[user_id scope], unique: true, if_not_exists: true

    create_table :account_merges, if_not_exists: true do |t|
      t.references :guest_user, null: false, foreign_key: { to_table: :users }
      t.references :user, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.datetime :merged_at
      t.timestamps
    end
    add_index :account_merges, %i[guest_user_id user_id], unique: true, if_not_exists: true

    create_table :moderation_flags, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: true
      t.string :flaggable_type, null: false
      t.integer :flaggable_id, null: false
      t.string :kind, null: false
      t.string :status, null: false, default: "open"
      t.text :reason
      t.timestamps
    end
    add_index :moderation_flags, %i[flaggable_type flaggable_id], if_not_exists: true
    add_index :moderation_flags, %i[user_id status], if_not_exists: true
  end

  def down
    # Do not drop tables that may already hold production rows.
  end
end
