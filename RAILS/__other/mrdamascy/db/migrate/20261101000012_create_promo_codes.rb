# frozen_string_literal: true

class CreatePromoCodes < ActiveRecord::Migration[8.0]
  def change
    create_table :promo_codes do |t|
      t.string :code, null: false
      t.string :kind, null: false
      t.integer :value
      t.integer :min_basket_ore, default: 0, null: false
      t.boolean :active, default: true, null: false
      t.string :description

      t.timestamps
    end
    add_index :promo_codes, :code, unique: true
  end
end
