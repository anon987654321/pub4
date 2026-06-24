# frozen_string_literal: true

class CreateMarketplaceListingFavorites < ActiveRecord::Migration[8.1]
  def change
    create_table :marketplace_listing_favorites do |t|
      t.references :user, null: false, foreign_key: true
      t.references :listing, null: false, foreign_key: { to_table: :marketplace_listings }
      t.timestamps
    end

    add_index :marketplace_listing_favorites,
              %i[user_id listing_id],
              unique: true,
              name: 'idx_marketplace_favorites_user_listing'
  end
end
