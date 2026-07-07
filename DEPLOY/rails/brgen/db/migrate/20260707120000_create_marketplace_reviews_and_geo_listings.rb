# frozen_string_literal: true

class CreateMarketplaceReviewsAndGeoListings < ActiveRecord::Migration[8.1]
  def change
    create_table :marketplace_reviews do |t|
      t.references :user, null: false, foreign_key: true
      t.references :listing, null: false, foreign_key: { to_table: :marketplace_listings }
      t.integer :rating, null: false
      t.text :body
      t.decimal :reviewer_lat, precision: 10, scale: 7
      t.decimal :reviewer_lng, precision: 10, scale: 7
      t.timestamps
    end

    add_index :marketplace_reviews, %i[listing_id created_at]
    add_index :marketplace_reviews, %i[user_id listing_id], unique: true

    add_column :marketplace_listings, :latitude, :decimal, precision: 10, scale: 7
    add_column :marketplace_listings, :longitude, :decimal, precision: 10, scale: 7
    add_column :marketplace_listings, :reviews_count, :integer, default: 0, null: false
    add_column :marketplace_listings, :rating, :decimal, precision: 3, scale: 2, default: 0, null: false
    add_index :marketplace_listings, %i[latitude longitude]
  end
end
