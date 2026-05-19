# frozen_string_literal: true

class CreateTakeawayRestaurants < ActiveRecord::Migration[8.1]
  def change
    create_table :takeaway_restaurants do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name
      t.text :description
      t.string :address
      t.string :city
      t.string :phone
      t.string :cuisine_type
      t.integer :delivery_fee_cents
      t.integer :min_order_cents
      t.decimal :rating
      t.integer :reviews_count
      t.boolean :active

      t.timestamps
    end
  end
end
