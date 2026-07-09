# frozen_string_literal: true

class HardenTakeawayGeoAvailabilityAndOrders < ActiveRecord::Migration[8.1]
  def change
    change_column_default :takeaway_menu_items, :available, from: nil, to: true
    change_column_null :takeaway_menu_items, :available, false, true
    add_index :takeaway_restaurants, %i[latitude longitude]
    add_index :takeaway_orders, %i[restaurant_id status updated_at]
  end
end
