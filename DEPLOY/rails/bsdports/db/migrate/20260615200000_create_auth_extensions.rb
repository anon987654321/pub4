# frozen_string_literal: true

class CreateAuthExtensions < ActiveRecord::Migration[8.1]
  def change
    change_table :users, bulk: true do |t|
      t.string :remember_token
      t.datetime :remember_token_expires_at
      t.string :magic_link_token
      t.datetime :magic_link_expires_at
      t.string :otp_secret
      t.boolean :two_factor_enabled, default: false, null: false
      t.string :last_login_country
      t.datetime :deleted_at
      t.datetime :deletion_scheduled_at
    end

    create_table :device_logins do |t|
      t.references :user, null: false, foreign_key: true
      t.string :fingerprint_hash, null: false
      t.string :user_agent
      t.string :accept_language
      t.string :timezone
      t.string :ip_address
      t.datetime :last_seen_at
      t.timestamps
    end

    add_index :device_logins, %i[user_id fingerprint_hash], unique: true

    create_table :authentications do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :uid, null: false
      t.json :info, default: {}
      t.timestamps
    end

    add_index :authentications, %i[provider uid], unique: true
  end
end