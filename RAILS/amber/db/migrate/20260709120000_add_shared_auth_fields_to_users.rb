# frozen_string_literal: true

class AddSharedAuthFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :remember_token, :string unless column_exists?(:users, :remember_token)
    add_column :users, :remember_token_expires_at, :datetime unless column_exists?(:users, :remember_token_expires_at)
    add_column :users, :magic_link_token, :string unless column_exists?(:users, :magic_link_token)
    add_column :users, :magic_link_expires_at, :datetime unless column_exists?(:users, :magic_link_expires_at)
    add_column :users, :deletion_scheduled_at, :datetime unless column_exists?(:users, :deletion_scheduled_at)
    add_column :users, :deleted_at, :datetime unless column_exists?(:users, :deleted_at)
    add_column :users, :otp_secret, :string unless column_exists?(:users, :otp_secret)
    add_column :users, :two_factor_enabled, :boolean, default: false, null: false unless column_exists?(:users, :two_factor_enabled)

    add_index :users, :remember_token, unique: true unless index_exists?(:users, :remember_token)
    add_index :users, :magic_link_token, unique: true unless index_exists?(:users, :magic_link_token)
    add_index :users, :deletion_scheduled_at unless index_exists?(:users, :deletion_scheduled_at)
  end
end
