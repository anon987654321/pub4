# frozen_string_literal: true

# When the buyer confirmed the parcel arrived, or the confirmation window ran
# out with no complaint. A seller saying "delivered" no longer creates the
# shop's payout; this moment does. Orders already delivered under the old rule
# had their payout created at delivery, so they count as confirmed then.
class AddReceiptConfirmedAtToMarketplaceOrders < ActiveRecord::Migration[8.1]
  def up
    add_column :marketplace_orders, :receipt_confirmed_at, :datetime
    execute <<~SQL.squish
      UPDATE marketplace_orders SET receipt_confirmed_at = delivered_at
      WHERE fulfilment_status = 'delivered' AND delivered_at IS NOT NULL
    SQL
  end

  def down
    remove_column :marketplace_orders, :receipt_confirmed_at
  end
end
