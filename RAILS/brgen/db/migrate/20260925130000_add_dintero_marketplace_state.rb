# frozen_string_literal: true

class AddDinteroMarketplaceState < ActiveRecord::Migration[8.1]
  def change
    change_table :marketplace_orders, bulk: true do |t|
      t.string :dintero_session_id, limit: 128
      t.string :dintero_transaction_id, limit: 128
    end
    add_index :marketplace_orders, :dintero_session_id
    add_index :marketplace_orders, :dintero_transaction_id

    change_table :marketplace_checkouts, bulk: true do |t|
      t.string :dintero_session_id, limit: 128
      t.string :dintero_transaction_id, limit: 128
    end
    add_index :marketplace_checkouts, :dintero_session_id
    add_index :marketplace_checkouts, :dintero_transaction_id

    change_table :marketplace_stores, bulk: true do |t|
      t.string :dintero_payout_destination_id, limit: 128
      t.string :dintero_payout_destination_status, limit: 64
    end
    add_index :marketplace_stores, :dintero_payout_destination_id, unique: true

    create_table :marketplace_webhook_deliveries do |t|
      t.string :provider, null: false, limit: 32
      t.string :event_delivery, null: false, limit: 128
      t.string :event, null: false, limit: 128
      t.string :status, null: false, default: "processing", limit: 32
      t.integer :attempts, null: false, default: 0
      t.datetime :received_at, null: false
      t.datetime :succeeded_at
      t.string :last_error, limit: 500
      t.timestamps
    end
    add_index :marketplace_webhook_deliveries,
              %i[provider event_delivery],
              unique: true,
              name: "index_marketplace_webhook_deliveries_identity"
    add_index :marketplace_webhook_deliveries, :status
  end
end
