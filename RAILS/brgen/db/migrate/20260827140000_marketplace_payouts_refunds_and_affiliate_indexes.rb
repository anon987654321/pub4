# frozen_string_literal: true

class MarketplacePayoutsRefundsAndAffiliateIndexes < ActiveRecord::Migration[8.1]
  def change
    add_column :marketplace_stores, :stripe_connect_id, :string, limit: 128
    add_column :marketplace_returns, :refund_reference, :string, limit: 128

    create_table :marketplace_payouts do |t|
      t.bigint :store_id, null: false
      t.bigint :order_id
      t.integer :amount_cents, null: false
      t.string :currency, limit: 8, null: false
      t.string :status, null: false, default: "pending"
      t.string :stripe_transfer_id, limit: 128
      t.string :blocked_reason, limit: 500
      t.datetime :sent_at
      t.timestamps
    end
    add_index :marketplace_payouts, :store_id
    add_index :marketplace_payouts, :order_id, unique: true
    add_index :marketplace_payouts, :status
    add_foreign_key :marketplace_payouts, :marketplace_stores, column: :store_id
    add_foreign_key :marketplace_payouts, :marketplace_orders, column: :order_id

    add_index :affiliate_conversions, :event_type_id
    add_index :affiliate_conversions, :program_id
    add_index :affiliate_conversions, :site_id
    add_index :affiliate_vouchers, :program_id
    add_index :affiliate_vouchers, :voucher_type_id
  end
end
