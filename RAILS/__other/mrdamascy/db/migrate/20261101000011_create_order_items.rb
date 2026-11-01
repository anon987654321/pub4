# frozen_string_literal: true

class CreateOrderItems < ActiveRecord::Migration[8.0]
  def change
    create_table :order_items do |t|
      t.references :order, null: false, foreign_key: true
      t.integer :menu_item_id
      t.string :name, null: false
      t.string :emoji
      t.integer :quantity, default: 1, null: false
      t.integer :unit_price_ore, null: false
      t.string :options_text
      t.integer :line_total_ore, null: false

      t.timestamps
    end
    add_index :order_items, :menu_item_id
  end
end
