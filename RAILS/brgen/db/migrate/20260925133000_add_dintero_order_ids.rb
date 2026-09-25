# frozen_string_literal: true

class AddDinteroOrderIds < ActiveRecord::Migration[8.1]
  def change
    add_column :marketplace_orders, :dintero_order_id, :string, limit: 128
    add_index :marketplace_orders, :dintero_order_id, unique: true

    add_column :marketplace_checkouts, :dintero_order_id, :string, limit: 128
    add_index :marketplace_checkouts, :dintero_order_id, unique: true
  end
end
