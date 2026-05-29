# frozen_string_literal: true

class AddDeliveryDriverToTakeawayOrders < ActiveRecord::Migration[8.1]
  def change
    add_reference :takeaway_orders, :delivery_driver, foreign_key: { to_table: :takeaway_delivery_drivers }, if_not_exists: true
    add_index :takeaway_orders, %i[delivery_driver_id status], if_not_exists: true
  end
end
