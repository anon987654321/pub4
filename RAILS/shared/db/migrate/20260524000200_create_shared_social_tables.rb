# frozen_string_literal: true

class CreateSharedSocialTables < ActiveRecord::Migration[8.0]
  def change
    create_table :reactions, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: true
      t.references :reactable, null: false, polymorphic: true
      t.string :kind, null: false, default: "like"
      t.timestamps
    end
    add_index :reactions, %i[user_id reactable_type reactable_id kind], unique: true, name: "idx_reactions_unique_user_target_kind"

    create_table :follows, if_not_exists: true do |t|
      t.references :follower, null: false, foreign_key: { to_table: :users }
      t.references :followable, null: false, polymorphic: true
      t.timestamps
    end
    add_index :follows, %i[follower_id followable_type followable_id], unique: true, name: "idx_follows_unique_follower_target"

    create_table :notifications, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: true
      t.references :actor, foreign_key: { to_table: :users }
      t.references :notifiable, polymorphic: true
      t.string :kind, null: false
      t.datetime :read_at
      t.json :payload
      t.timestamps
    end
    add_index :notifications, %i[user_id read_at]
    add_index :notifications, %i[user_id created_at]

    create_table :review_cases, if_not_exists: true do |t|
      t.references :reporter, foreign_key: { to_table: :users }
      t.references :reviewer, foreign_key: { to_table: :users }
      t.references :reviewable, null: false, polymorphic: true
      t.string :state, null: false, default: "open"
      t.string :reason
      t.text :notes
      t.datetime :reviewed_at
      t.timestamps
    end
    add_index :review_cases, %i[state created_at]
    add_index :review_cases, %i[reviewable_type reviewable_id]
  end
end
