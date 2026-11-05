# frozen_string_literal: true

class CreateMenuItems < ActiveRecord::Migration[8.0]
  def change
    create_table :menu_items do |t|
      t.references :menu_category, null: false, foreign_key: true
      t.string :name, null: false
      t.string :name_en
      t.string :description
      t.string :description_en
      t.integer :price_ore, null: false
      t.string :origin
      t.string :emoji
      t.integer :heat, default: 0, null: false
      t.string :badges
      t.integer :weight_g
      t.integer :position
      t.boolean :available, default: true, null: false

      t.timestamps
    end
    add_index :menu_items, [ :menu_category_id, :position ]
    add_index :menu_items, :position
    add_index :menu_items, :available
  end
end
