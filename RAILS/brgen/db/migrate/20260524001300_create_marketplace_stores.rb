# frozen_string_literal: true

class CreateMarketplaceStores < ActiveRecord::Migration[8.0]
  def change
    create_table :marketplace_stores, if_not_exists: true do |t|
      t.references :owner, null: false, foreign_key: { to_table: :users }
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :vertical
      t.boolean :active, null: false, default: true
      t.boolean :verified, null: false, default: false
      t.timestamps
    end

    add_index :marketplace_stores, :slug, unique: true, if_not_exists: true
    add_index :marketplace_stores, %i[vertical active], if_not_exists: true
    add_reference :marketplace_listings, :store, foreign_key: { to_table: :marketplace_stores }, if_not_exists: true
  end
end
