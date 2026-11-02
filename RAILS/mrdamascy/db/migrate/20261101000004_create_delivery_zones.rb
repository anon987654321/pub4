# frozen_string_literal: true

class CreateDeliveryZones < ActiveRecord::Migration[8.0]
  def change
    create_table :delivery_zones do |t|
      t.string :postcode, null: false
      t.string :name, null: false
      t.integer :fee_ore, null: false
      t.integer :min_basket_ore, null: false
      t.integer :eta_minutes, null: false

      t.timestamps
    end
    add_index :delivery_zones, :postcode, unique: true
  end
end
