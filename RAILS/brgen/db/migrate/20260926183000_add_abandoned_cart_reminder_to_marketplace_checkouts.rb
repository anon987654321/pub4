# frozen_string_literal: true

class AddAbandonedCartReminderToMarketplaceCheckouts < ActiveRecord::Migration[8.1]
  def change
    add_column :marketplace_checkouts, :abandoned_cart_reminded_at, :datetime
    add_index :marketplace_checkouts,
              [ :status, :abandoned_cart_reminded_at, :updated_at ],
              name: "index_marketplace_checkouts_on_abandoned_cart_reminder"
  end
end
