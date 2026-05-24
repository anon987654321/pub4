# frozen_string_literal: true

class CreateBrgenSocialTables < ActiveRecord::Migration[8.0]
  def change
    create_table :follows, if_not_exists: true do |t|
      t.references :follower, null: false, foreign_key: { to_table: :users }
      t.references :followed, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :follows, %i[follower_id followed_id], unique: true, if_not_exists: true

    create_table :reactions, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: true
      t.references :reactable, polymorphic: true
      t.references :post, foreign_key: true
      t.string :kind, null: false, default: "like"
      t.timestamps
    end
    add_index :reactions,
              %i[user_id reactable_type reactable_id post_id kind],
              unique: true,
              name: "idx_reactions_unique_user_target_kind",
              if_not_exists: true

    create_table :notifications, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: true
      t.references :actor, foreign_key: { to_table: :users }
      t.references :notifiable, polymorphic: true
      t.string :kind, null: false
      t.datetime :read_at
      t.json :payload
      t.timestamps
    end
    add_index :notifications, %i[user_id read_at], if_not_exists: true
    add_index :notifications, %i[user_id created_at], if_not_exists: true
  end
end
