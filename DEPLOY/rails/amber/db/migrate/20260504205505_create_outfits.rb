# frozen_string_literal: true

class CreateOutfits < ActiveRecord::Migration[8.1]
  def change
    create_table :outfits do |t|
      t.string :name
      t.text :description
      t.string :category
      t.string :season
      t.string :occasion
      t.integer :likes_count
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
