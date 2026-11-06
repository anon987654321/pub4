# frozen_string_literal: true

# A pending cart is a promise the kitchen has not accepted yet. Without an
# expiry it sits open forever: the reader forgets it, the restaurant's order
# list fills with abandoned baskets, and "pending" stops meaning anything.
#
# Only immediate carts get a deadline. A scheduled order is a deliberate
# placement for a future time — expiring it on a clock would cancel orders
# people fully intend to have, so scheduled rows keep a nil expires_at and
# the same lifetime they always had.
class AddExpiresAtToTakeawayOrders < ActiveRecord::Migration[8.2]
  def change
    add_column :takeaway_orders, :expires_at, :datetime
    # The sweep reads exactly this pair every 15 minutes; the user-facing
    # ticket page reads by id and needs nothing new.
    add_index :takeaway_orders, %i[status expires_at], name: "index_takeaway_orders_on_status_and_expires_at"
  end
end
