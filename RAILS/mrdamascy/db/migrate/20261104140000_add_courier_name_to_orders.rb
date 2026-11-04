# frozen_string_literal: true

# The staff board named every Wolt dispatch "Bergen Bud", whoever carried
# the bag; the order now keeps the courier Wolt Drive names.
class AddCourierNameToOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :orders, :courier_name, :string
  end
end
