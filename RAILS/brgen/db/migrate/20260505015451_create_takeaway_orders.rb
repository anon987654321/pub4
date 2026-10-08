# frozen_string_literal: true

class CreateTakeawayOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :takeaway_orders do |t|
      t.references :user, null: false, foreign_key: true
      t.references :restaurant, null: false, foreign_key: { to_table: :takeaway_restaurants }
      t.string :status
      t.string :delivery_address
      t.integer :subtotal_cents
      t.integer :delivery_fee_cents
      t.integer :total_cents
      t.text :special_instructions

      t.timestamps
    end
  end
end
