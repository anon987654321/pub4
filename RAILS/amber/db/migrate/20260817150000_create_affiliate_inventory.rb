# frozen_string_literal: true

# The affiliate inventory tables, so amber can carry the same stock brgen does.
#
# All three lived only in brgen, and with them the whole read path. amber had
# AffiliateLink — a URL an owner pastes onto one wardrobe item — and no network
# inventory at all, so ShopTheLook could rank saved links and nothing else, and
# there was no in-feed affiliate surface to speak of.
#
# Copied from brgen's schema rather than sharing its database: the two apps have
# separate SQLite files and always have. Same table names on both sides, so
# Shared::AffiliateProduct declares table_name once and serves either.
#
# One migration per app, which is this repo's convention — the engine declares
# config.paths["db/migrate"] but the apps do not read it. Guarded, so re-running
# is free.
class CreateAffiliateInventory < ActiveRecord::Migration[8.1]
  def change
    return if table_exists?(:affiliate_products)

    create_table "affiliate_products", force: :cascade do |t|
      t.string "category", limit: 120
      t.text "click_url", null: false
      t.decimal "commission_rate", precision: 6, scale: 3
      t.datetime "created_at", null: false
      t.string "currency", limit: 8
      t.text "description"
      t.string "external_id", limit: 128, null: false
      t.text "image_url"
      t.boolean "in_stock", default: true, null: false
      t.datetime "last_seen_at"
      t.string "market", limit: 8
      t.string "merchant", limit: 200
      t.boolean "placeholder", default: false, null: false
      t.integer "price_cents"
      t.string "program_id", limit: 64
      t.string "source", limit: 32, null: false
      t.string "title", limit: 300, null: false
      t.datetime "updated_at", null: false
      t.index [ "last_seen_at" ], name: "index_affiliate_products_on_last_seen_at"
      t.index [ "market", "category", "last_seen_at" ], name: "index_affiliate_products_on_market_category_freshness"
      t.index [ "source", "external_id" ], name: "index_affiliate_products_on_source_and_external_id", unique: true
    end
    create_table "affiliate_vouchers", force: :cascade do |t|
      t.string "code", limit: 256
      t.datetime "created_at", null: false
      t.string "currency", limit: 8
      t.text "description"
      t.decimal "discount_amount", precision: 10, scale: 2
      t.datetime "ends_at"
      t.boolean "exclusive", default: false, null: false
      t.string "external_id", limit: 64, null: false
      t.text "landing_url"
      t.datetime "last_seen_at"
      t.string "market", limit: 8
      t.boolean "percentage", default: false, null: false
      t.string "program_id", limit: 64
      t.string "program_name", limit: 200
      t.string "short_description", limit: 200
      t.boolean "site_specific", default: false, null: false
      t.string "source", limit: 32, default: "tradedoubler", null: false
      t.datetime "starts_at"
      t.string "title", limit: 120, null: false
      t.text "track_url", null: false
      t.datetime "updated_at", null: false
      t.integer "voucher_type_id", default: 1, null: false
      t.index [ "market", "ends_at" ], name: "index_affiliate_vouchers_on_market_and_ends_at"
      t.index [ "site_specific" ], name: "index_affiliate_vouchers_on_site_specific"
      t.index [ "source", "external_id" ], name: "index_affiliate_vouchers_on_source_and_external_id", unique: true
    end
    create_table "affiliate_conversions", force: :cascade do |t|
      t.datetime "created_at", null: false
      t.string "currency", limit: 8
      t.string "epi", limit: 500
      t.string "epi2", limit: 500
      t.integer "event_type_id"
      t.string "legacy_transaction_id", limit: 128
      t.integer "message_type_id", null: false
      t.string "order_number", limit: 128
      t.decimal "order_value", precision: 12, scale: 2
      t.string "product_id", limit: 128
      t.string "product_name", limit: 300
      t.integer "program_id"
      t.decimal "publisher_commission", precision: 12, scale: 2
      t.json "raw_payload"
      t.string "sequence_number", limit: 64
      t.integer "site_id"
      t.string "site_name", limit: 200
      t.string "source", limit: 32, default: "tradedoubler", null: false
      t.datetime "time_of_event"
      t.datetime "time_of_visit"
      t.string "transaction_id", limit: 128
      t.datetime "updated_at", null: false
      t.string "visitor_id", limit: 128
      t.index [ "created_at" ], name: "index_affiliate_conversions_on_created_at"
      t.index [ "epi" ], name: "index_affiliate_conversions_on_epi"
      t.index [ "message_type_id" ], name: "index_affiliate_conversions_on_message_type_id"
      t.index [ "order_number" ], name: "index_affiliate_conversions_on_order_number"
      t.index [ "source", "transaction_id", "message_type_id" ], name: "index_affiliate_conversions_on_source_txn_message", unique: true
    end
  end
end
