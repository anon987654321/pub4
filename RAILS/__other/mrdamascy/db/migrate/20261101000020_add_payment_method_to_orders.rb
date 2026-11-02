# frozen_string_literal: true

# Operator-mandated second payment lane (Stripe Checkout alongside Vipps).
# Additive only: one column telling each order which PSP owns its payment, so
# webhook events and tracking-page syncs route to the right client. Existing
# orders keep the default ("vipps"), so replaying old rows changes nothing.
class AddPaymentMethodToOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :orders, :payment_method, :string, default: "vipps", null: false
    add_index :orders, :payment_method
  end
end
