# frozen_string_literal: true

class CreateTakeawayMenuItems < ActiveRecord::Migration[8.1]
  def change
    create_table :takeaway_menu_items do |t|
      t.references :restaurant, null: false, foreign_key: { to_table: :takeaway_restaurants }
      t.string :name
      t.text :description
      t.integer :price_cents
      t.boolean :available
      t.boolean :vegetarian
      t.boolean :vegan

      t.timestamps
    end
  end
end
