# frozen_string_literal: true

class CreateMenuCategories < ActiveRecord::Migration[8.0]
  def change
    create_table :menu_categories do |t|
      t.references :kitchen, null: false, foreign_key: true
      t.string :name, null: false
      t.string :name_en
      t.string :slug, null: false
      t.string :emoji
      t.integer :position

      t.timestamps
    end
    add_index :menu_categories, [ :kitchen_id, :position ]
    add_index :menu_categories, :slug, unique: true
  end
end
