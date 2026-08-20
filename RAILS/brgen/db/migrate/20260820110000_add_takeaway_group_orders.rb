# frozen_string_literal: true

# One ticket, several people, one delivery.
#
# Ordering for an office or a flat meant one person collecting everybody's
# choices in a chat and typing them in, which is where the wrong lunch comes
# from. A group order is the same Takeaway::Order with a link: the line knows
# who added it, and the host is the only one who can send it to the kitchen.
class AddTakeawayGroupOrders < ActiveRecord::Migration[8.1]
  def change
    # Whose line this is. Nullable, because every order that predates this is
    # the host's own and backfilling a guess would be worse than saying nothing.
    add_reference :takeaway_order_items, :user, null: true, foreign_key: true

    # The shareable half. A token rather than the id: an order id in a link
    # people paste into a group chat is an invitation to read somebody else's
    # lunch by counting.
    add_column :takeaway_orders, :group_token, :string
    add_column :takeaway_orders, :group_open, :boolean, null: false, default: false
    add_index :takeaway_orders, :group_token, unique: true
  end
end
