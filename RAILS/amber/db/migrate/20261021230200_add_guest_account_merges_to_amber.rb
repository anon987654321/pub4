# frozen_string_literal: true

# Amber uses persisted guest identities for anonymous posts and MASTER chat.
# This audit row lets the shared account merger record the conversion exactly
# like Brgen does, without storing a copy of the guest's content.
class AddGuestAccountMergesToAmber < ActiveRecord::Migration[8.1]
  def up
    create_table :account_merges, if_not_exists: true do |t|
      t.references :guest_user, null: false, foreign_key: { to_table: :users }
      t.references :user, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.datetime :merged_at
      t.timestamps
    end
    add_index :account_merges, %i[guest_user_id user_id], unique: true,
                                                           if_not_exists: true
  end

  def down
    # Keep merge audit history rather than deleting account-conversion evidence.
  end
end
