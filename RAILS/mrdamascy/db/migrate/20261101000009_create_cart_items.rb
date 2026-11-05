# frozen_string_literal: true

class CreateCartItems < ActiveRecord::Migration[8.0]
  def change
    create_table :cart_items do |t|
      t.references :cart, null: false, foreign_key: true
      t.references :menu_item, null: false, foreign_key: true
      t.integer :quantity, default: 1, null: false
      t.string :option_ids
      t.string :note
      t.integer :unit_price_ore, null: false

      t.timestamps
    end
    add_index :cart_items, [ :cart_id, :menu_item_id ]
  end
end
