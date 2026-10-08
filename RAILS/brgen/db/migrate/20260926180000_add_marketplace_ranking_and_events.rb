# frozen_string_literal: true

class AddMarketplaceRankingAndEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :marketplace_listings, :delivery_promise, :integer, default: 3, null: false
    add_column :marketplace_listings, :fulfilment_method, :integer, default: 0, null: false
    add_column :marketplace_listings, :ranking_score, :float, default: 0.0, null: false
    add_column :marketplace_listings, :seller_score, :float, default: 0.8, null: false

    add_index :marketplace_listings, :delivery_promise
    add_index :marketplace_listings, :ranking_score
    add_index :marketplace_listings, %i[city_id ranking_score],
              name: "index_marketplace_listings_on_city_and_ranking"

    create_table :marketplace_listing_events do |t|
      t.references :listing, null: false, foreign_key: { to_table: :marketplace_listings }
      t.references :user, null: true, foreign_key: true
      t.string :event_type, null: false
      t.text :metadata, null: false, default: "{}"
      t.datetime :occurred_at, null: false
      t.timestamps
    end

    add_index :marketplace_listing_events, %i[listing_id event_type occurred_at],
              name: "index_marketplace_listing_events_on_listing_type_time"
    add_index :marketplace_listing_events, :occurred_at
  end
end
