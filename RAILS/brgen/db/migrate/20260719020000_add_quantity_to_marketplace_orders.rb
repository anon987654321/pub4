# frozen_string_literal: true

class AddQuantityToMarketplaceOrders < ActiveRecord::Migration[8.1]
  def change
    return if column_exists?(:marketplace_orders, :quantity)

    add_column :marketplace_orders, :quantity, :integer, default: 1, null: false
  end
end
