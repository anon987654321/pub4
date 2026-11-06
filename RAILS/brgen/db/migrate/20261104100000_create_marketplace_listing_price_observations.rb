# frozen_string_literal: true

# The honest anchor's evidence. Omnibus Art. 6a lets a deal say "was X" only
# when X was the lowest applicable price in the 30 days before the reduction,
# and marketplace_listings.price_cents is mutable state with no history — any
# "was" price rendered from it would be seller folklore. This table records
# every price a listing actually carried, written by Listing's create/update
# hooks, and Marketplace::Listing#omnibus_reference_price_cents reads the
# trailing 30-day minimum from it. A card renders the anchor only when that
# minimum is strictly above the current price (persuasion_honesty contract).
class CreateMarketplaceListingPriceObservations < ActiveRecord::Migration[8.1]
  def change
    create_table :marketplace_listing_price_observations do |t|
      t.integer "listing_id", null: false
      t.integer "price_cents", null: false
      t.datetime "observed_at", null: false
      t.timestamps
    end

    add_index :marketplace_listing_price_observations, :listing_id,
      name: "index_marketplace_price_observations_on_listing"
    add_index :marketplace_listing_price_observations, [ :listing_id, :observed_at ],
      name: "index_marketplace_price_observations_on_listing_time"
  end
end
