# frozen_string_literal: true

class CreateTakeawayReviews < ActiveRecord::Migration[8.1]
  def change
    create_table :takeaway_reviews do |t|
      t.references :user, null: false, foreign_key: true
      t.references :order, null: false, foreign_key: { to_table: :takeaway_orders }
      t.references :restaurant, null: false, foreign_key: { to_table: :takeaway_restaurants }
      t.integer :rating, null: false
      t.text :body
      t.decimal :reviewer_lat, precision: 10, scale: 7
      t.decimal :reviewer_lng, precision: 10, scale: 7
      t.timestamps
    end

    add_index :takeaway_reviews, %i[restaurant_id created_at], if_not_exists: true

    # support hyperlocal by adding location to restaurants (geocode + neighbour radius)
    add_column :takeaway_restaurants, :latitude, :decimal, precision: 10, scale: 7
    add_column :takeaway_restaurants, :longitude, :decimal, precision: 10, scale: 7
  end
end
