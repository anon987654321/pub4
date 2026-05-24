# frozen_string_literal: true

class CreateTakeawayFavoriteRestaurants < ActiveRecord::Migration[8.1]
  def change
    create_table :takeaway_favorite_restaurants do |t|
      t.references :user, null: false, foreign_key: true
      t.references :restaurant, null: false, foreign_key: { to_table: :takeaway_restaurants }
      t.timestamps
    end

    add_index :takeaway_favorite_restaurants,
              %i[user_id restaurant_id],
              unique: true,
              name: "idx_takeaway_favorites_user_restaurant"
  end
end
