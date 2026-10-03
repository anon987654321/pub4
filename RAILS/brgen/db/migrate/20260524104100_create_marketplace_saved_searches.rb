# frozen_string_literal: true

class CreateMarketplaceSavedSearches < ActiveRecord::Migration[8.1]
  def change
    create_table :marketplace_saved_searches do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name
      t.string :query
      t.integer :category_id
      t.string :location
      t.boolean :notify, null: false, default: false
      t.timestamps
    end
  end
end
