# frozen_string_literal: true

# A real basket.
#
# Marketplace::Order is a per-listing offer with its own payment, which is the
# right shape for classifieds — a bike from a stranger is negotiated, not added
# to a cart. It is the wrong shape for a shop: buying four things from a store
# meant four payments, four PSP round trips and four card charges, and there was
# nowhere to put a delivery address.
#
# So this adds the basket *above* the orders rather than replacing them: one
# Checkout carries the address and the single payment, and the per-listing
# orders stay exactly as they were. Both shapes keep working.
class CreateMarketplaceCheckouts < ActiveRecord::Migration[8.1]
  def change
    create_table :marketplace_addresses do |t|
      t.references :user, null: false, foreign_key: true
      t.string :recipient, null: false
      t.string :line1, null: false
      t.string :line2
      t.string :postcode, null: false
      t.string :city_name, null: false
      t.string :country_code, null: false, default: "NO"
      t.string :phone
      t.boolean :default_address, null: false, default: false
      t.timestamps
    end
    add_index :marketplace_addresses, %i[user_id default_address]

    create_table :marketplace_checkouts do |t|
      t.references :user, null: false, foreign_key: true
      t.references :marketplace_address, foreign_key: true
      t.string   :status, null: false, default: "open"
      t.string   :payment_provider
      t.string   :payment_reference
      t.integer  :total_cents, null: false, default: 0
      t.string   :currency, null: false, default: "NOK"
      t.datetime :paid_at
      t.timestamps
    end
    add_index :marketplace_checkouts, %i[user_id status]

    change_table :marketplace_orders, bulk: true do |t|
      t.references :marketplace_checkout, foreign_key: true
      # Fulfilment is a separate axis from payment: a paid order that has not
      # shipped and a shipped order awaiting payment are both real states, and
      # collapsing them into one status column is why "where is my parcel" is
      # unanswerable on most small shops.
      t.string   :fulfilment_status, null: false, default: "unfulfilled"
      t.string   :tracking_code
      t.string   :carrier
      t.datetime :shipped_at
      t.datetime :delivered_at
    end
    add_index :marketplace_orders, %i[fulfilment_status]

    # nil means one of a kind, which is what a classifieds listing is. A number
    # means a shop with inventory. Defaulting to 1 would have made every private
    # sale look like a shop with one left.
    add_column :marketplace_listings, :stock, :integer
  end
end
