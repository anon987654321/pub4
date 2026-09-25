# frozen_string_literal: true

class AllowSharedDinteroOrderIds < ActiveRecord::Migration[8.1]
  def change
    remove_index :marketplace_orders, :dintero_order_id,
                 unique: true,
                 name: "index_marketplace_orders_on_dintero_order_id"
    add_index :marketplace_orders, :dintero_order_id
  end
end
