# frozen_string_literal: true

# Wolt Drive overflow dispatch (APP_SPEC §5 analog for couriers): when the
# kitchen wants a last-mile carrier for its own order, the delivery request id
# and live tracking URL are stored on the order. Mock mode stores
# "wolt-mock-…"-shaped ids, real mode stores Wolt's delivery uuid.
class AddExternalDeliveryToOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :orders, :external_delivery_id, :string
    add_column :orders, :external_delivery_url, :string
  end
end
