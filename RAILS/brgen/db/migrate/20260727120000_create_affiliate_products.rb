# frozen_string_literal: true

# Persistence for affiliate inventory.
#
# Tradedoubler (app/services/tradedoubler.rb) fetched products live and cached
# them in Solid Cache for 15 minutes, with nothing behind that. Three
# consequences this table fixes:
#
#   1. Seed data could not contain affiliate products at all — there was no
#      table to seed. "Real affiliate products in the seeds" is impossible
#      without somewhere to put them.
#   2. Every cache miss was a blocking outbound HTTP call inside a page render,
#      and a TradeDoubler outage (or an unset token) silently emptied the deals
#      sidebar.
#   3. Nothing was auditable. Commission rates, click URLs and prices are the
#      records you need when reconciling an affiliate payout, and they only
#      ever existed in a volatile cache.
#
# Rows are upserted by [source, external_id] and stamped with last_seen_at, so
# an importer can age out products a feed has stopped returning without
# deleting history mid-render.
class CreateAffiliateProducts < ActiveRecord::Migration[8.1]
  def change
    create_table :affiliate_products do |t|
      # "tradedoubler", "amazon" — one table, several networks, because the
      # deals sidebar and the newsletter treat them identically.
      t.string :source, null: false, limit: 32
      # The network's own product id (TradeDoubler productId, Amazon ASIN).
      t.string :external_id, null: false, limit: 128

      t.string :title, null: false, limit: 300
      t.text :description
      t.string :merchant, limit: 200
      # TradeDoubler's program/advertiser id — needed to tie a click back to the
      # program that pays for it.
      t.string :program_id, limit: 64

      # Integer minor units, matching marketplace_listings.price_cents rather
      # than the feed's decimal string.
      t.integer :price_cents
      t.string :currency, limit: 8

      t.text :image_url
      # The tracking URL. Long: affiliate deep links carry sizeable payloads.
      t.text :click_url, null: false

      t.string :category, limit: 120
      # Country code. Affiliate programs are licensed per market, so a product
      # approved for NO must not be shown on the .us or .nl domains.
      t.string :market, limit: 8

      t.decimal :commission_rate, precision: 6, scale: 3
      t.boolean :in_stock, null: false, default: true
      # Placeholder rows seeded when no token is configured are flagged so they
      # can never be mistaken for real, payable inventory.
      t.boolean :placeholder, null: false, default: false

      t.datetime :last_seen_at
      t.timestamps
    end

    # Upsert key.
    add_index :affiliate_products, %i[source external_id], unique: true
    # Backs the deals sidebar: fresh, in-stock, market- and category-scoped.
    add_index :affiliate_products, %i[market category last_seen_at],
              name: "index_affiliate_products_on_market_category_freshness"
    add_index :affiliate_products, :last_seen_at
  end
end
