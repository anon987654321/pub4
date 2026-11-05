# frozen_string_literal: true

class CreateItemOptions < ActiveRecord::Migration[8.0]
  def change
    create_table :item_options do |t|
      t.references :menu_item, null: false, foreign_key: true
      t.string :name, null: false
      t.string :name_en
      t.integer :price_ore, default: 0, null: false
      t.string :kind, null: false
      t.boolean :default_on, default: false, null: false
      t.integer :position

      t.timestamps
    end
    add_index :item_options, [ :menu_item_id, :position ]
  end
end
