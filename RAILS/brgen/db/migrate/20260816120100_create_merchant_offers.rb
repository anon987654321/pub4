# frozen_string_literal: true

class CreateMerchantOffers < ActiveRecord::Migration[8.0]
  def change
    create_table :merchant_offers do |t|
      t.string :offer_id, null: false, limit: 50
      t.string :listing_type
      t.bigint :listing_id
      t.string :content_language, default: "nb", null: false
      t.string :feed_label, default: "NO", null: false
      t.string :google_status, default: "pending"
      t.datetime :last_pushed_at
      t.string :last_error, limit: 500
      t.string :gtin
      t.string :brand
      t.string :condition
      t.boolean :curated, default: true, null: false
      t.timestamps
    end

    add_index :merchant_offers, :offer_id, unique: true
    add_index :merchant_offers, %i[listing_type listing_id]
    add_index :merchant_offers, :google_status
  end
end
