# frozen_string_literal: true

class CreateOrders < ActiveRecord::Migration[8.0]
  def change
    create_table :orders do |t|
      t.references :user, foreign_key: true
      t.references :kitchen, null: false, foreign_key: true
      t.string :state, default: "placed", null: false
      t.string :delivery_mode
      t.string :address
      t.string :postcode
      t.string :phone
      t.integer :subtotal_ore
      t.integer :delivery_fee_ore
      t.integer :discount_ore, default: 0, null: false
      t.integer :tip_ore, default: 0, null: false
      t.integer :total_ore
      t.string :promo_code
      t.integer :eta_minutes
      t.string :tracking_token, null: false
      t.string :payment_state, default: "pending", null: false
      t.string :vipps_order_id
      t.string :vipps_url
      t.integer :payment_steps, default: 3, null: false
      t.boolean :express, default: true, null: false
      t.datetime :placed_at

      t.timestamps
    end
    add_index :orders, :tracking_token, unique: true
    add_index :orders, [ :user_id, :state ]
    add_index :orders, :state
    add_index :orders, :payment_state
  end
end
