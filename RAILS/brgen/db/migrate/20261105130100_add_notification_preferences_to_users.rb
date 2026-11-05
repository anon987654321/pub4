# frozen_string_literal: true

# Per-kind delivery choices from the account page: { "mention" => { "push" =>
# true, "email" => false }, ... }. Empty means every default (User::NotificationPreferences).
class AddNotificationPreferencesToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :notification_preferences, :json, default: {}, null: false
  end
end
