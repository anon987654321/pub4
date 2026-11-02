# frozen_string_literal: true

class CreateCarts < ActiveRecord::Migration[8.0]
  def change
    create_table :carts do |t|
      t.references :user, foreign_key: true
      t.string :session_key
      t.string :delivery_mode, default: "delivery", null: false

      t.timestamps
    end
    add_index :carts, :session_key
  end
end
