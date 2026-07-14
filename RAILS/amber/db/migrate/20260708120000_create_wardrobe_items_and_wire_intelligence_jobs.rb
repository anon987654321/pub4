# frozen_string_literal: true

class CreateWardrobeItemsAndWireIntelligenceJobs < ActiveRecord::Migration[8.1]
  def change
    create_table :wardrobe_items do |t|
      t.references :user, null: false, foreign_key: true
      t.references :item, null: false, foreign_key: true
      t.date :acquisition_date
      t.string :condition
      t.text :notes
      t.timestamps
    end
    add_index :wardrobe_items, %i[user_id item_id], unique: true
  end
end
