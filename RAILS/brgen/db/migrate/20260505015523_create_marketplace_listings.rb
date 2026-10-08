# frozen_string_literal: true

class CreateMarketplaceListings < ActiveRecord::Migration[8.1]
  def change
    create_table :marketplace_listings do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :category_id, null: false
      t.string :title
      t.text :description
      t.integer :price_cents
      t.string :currency
      t.string :condition
      t.string :status
      t.string :location
      t.integer :views_count

      t.timestamps
    end

    add_index :marketplace_listings, :category_id
    add_foreign_key :marketplace_listings, :marketplace_categories, column: :category_id
  end
end
