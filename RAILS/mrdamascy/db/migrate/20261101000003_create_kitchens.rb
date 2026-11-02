# frozen_string_literal: true

class CreateKitchens < ActiveRecord::Migration[8.0]
  def change
    create_table :kitchens do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :address
      t.string :postcode
      t.string :phone
      t.string :opening_hours
      t.float :rating, default: 4.9, null: false

      t.timestamps
    end
    add_index :kitchens, :slug, unique: true
  end
end
