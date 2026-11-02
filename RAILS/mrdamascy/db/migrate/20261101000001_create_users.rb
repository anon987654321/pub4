# frozen_string_literal: true

class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string :phone, null: false
      t.string :name
      t.integer :role, default: 0, null: false
      t.string :default_address
      t.string :default_postcode

      t.timestamps
    end
    add_index :users, :phone, unique: true
  end
end
