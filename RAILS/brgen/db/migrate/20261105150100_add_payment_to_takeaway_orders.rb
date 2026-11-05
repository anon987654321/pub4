# frozen_string_literal: true

# A takeaway order paid in the app. Until now the form said "arrange payment
# with the restaurant" and the table had nowhere to record money; the columns
# mirror marketplace_orders' so the Vipps webhook treats both the same way.
class AddPaymentToTakeawayOrders < ActiveRecord::Migration[8.1]
  def change
    change_table :takeaway_orders, bulk: true do |t|
      t.string :payment_status, default: "unpaid", null: false
      t.string :payment_provider
      t.string :payment_reference
      t.datetime :paid_at
    end
    add_index :takeaway_orders, :payment_reference
  end
end
