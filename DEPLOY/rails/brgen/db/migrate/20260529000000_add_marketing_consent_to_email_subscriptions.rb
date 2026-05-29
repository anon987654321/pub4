# frozen_string_literal: true

class AddMarketingConsentToEmailSubscriptions < ActiveRecord::Migration[8.1]
  def change
    add_column :email_subscriptions, :agreed_to_marketing, :boolean, default: false, null: false
    add_column :email_subscriptions, :interests, :text
  end
end
