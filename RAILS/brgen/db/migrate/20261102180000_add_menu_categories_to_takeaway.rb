# frozen_string_literal: true

class AddMenuCategoriesToTakeaway < ActiveRecord::Migration[8.2]
  def change
    create_table :takeaway_menu_categories do |t|
      t.references :restaurant, null: false, foreign_key: { to_table: :takeaway_restaurants }
      t.string :name, null: false, limit: 40

      t.timestamps
    end
    add_index :takeaway_menu_categories, [ :restaurant_id, :name ],
              unique: true, name: "index_takeaway_menu_categories_on_restaurant_and_name"
    add_reference :takeaway_menu_items, :menu_category,
                  foreign_key: { to_table: :takeaway_menu_categories }
  end
end
