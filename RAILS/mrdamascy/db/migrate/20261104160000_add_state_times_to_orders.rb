# frozen_string_literal: true

# An order kept only placed_at, so how long the kitchen took to confirm,
# cook and hand over, and the courier to deliver, could not be measured.
# Each move now stamps its own time.
class AddStateTimesToOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :orders, :confirmed_at, :datetime
    add_column :orders, :ready_at, :datetime
    add_column :orders, :picked_up_at, :datetime
    add_column :orders, :delivered_at, :datetime
  end
end
