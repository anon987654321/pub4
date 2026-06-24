# frozen_string_literal: true

class CreatePushSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :push_subscriptions do |t|
      t.belongs_to :user, null: false
      t.text :endpoint, null: false
      t.string :p256dh, null: false
      t.string :auth,   null: false
      t.timestamps
    end
    add_index :push_subscriptions, %i[user_id endpoint], unique: true
  end
end
