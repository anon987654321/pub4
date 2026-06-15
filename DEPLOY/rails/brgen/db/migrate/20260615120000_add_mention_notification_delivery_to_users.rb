# frozen_string_literal: true

class AddMentionNotificationDeliveryToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :mention_notification_delivery, :string, null: false, default: "push"
  end
end
