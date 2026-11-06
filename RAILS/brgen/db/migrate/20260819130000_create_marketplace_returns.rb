# frozen_string_literal: true

# Sending it back. Its own table rather than a column on the order, because a
# return has its own lifecycle — asked for, answered, received — and its own
# reason, which is the part the seller reads.
class CreateMarketplaceReturns < ActiveRecord::Migration[8.1]
  def change
    create_table :marketplace_returns do |t|
      t.references :order, null: false, foreign_key: { to_table: :marketplace_orders }
      t.references :resolved_by, null: true, foreign_key: { to_table: :users }
      t.string :status, null: false, default: "requested"
      t.text :reason, null: false
      t.text :resolution_note
      t.datetime :resolved_at
      # Set by whatever actually moves the money. Nothing does yet: neither
      # payment service has a refund call, so a received return sits here
      # unrefunded and says so rather than claiming the buyer has been paid.
      t.datetime :refunded_at
      t.timestamps
    end

    # One open return per order; a second is the same argument twice.
    add_index :marketplace_returns, %i[order_id status]
  end
end
