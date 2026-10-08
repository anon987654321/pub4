# frozen_string_literal: true

class AddPaymentFieldsToMarketplaceOrders < ActiveRecord::Migration[8.0]
  def change
    change_table :marketplace_orders, bulk: true do |t|
      t.string :payment_provider
      t.string :payment_status, null: false, default: "unpaid"
      t.string :payment_reference
      t.datetime :paid_at
    end
    add_index :marketplace_orders, :payment_status
    add_index :marketplace_orders, :payment_reference
  end
end
