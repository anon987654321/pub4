# frozen_string_literal: true

class CreateLoyaltyStamps < ActiveRecord::Migration[8.0]
  def change
    create_table :loyalty_stamps do |t|
      t.references :user, null: false, foreign_key: true
      t.references :order, foreign_key: true
      t.boolean :redeemed, default: false, null: false
      t.datetime :awarded_at

      t.timestamps
    end
    add_index :loyalty_stamps, [ :user_id, :redeemed ]
  end
end
