class CreateMarketplaceListings < ActiveRecord::Migration[8.1]
  def change
    create_table :marketplace_listings do |t|
      t.references :user, null: false, foreign_key: true
      t.references :category, null: false, foreign_key: true
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
  end
end
