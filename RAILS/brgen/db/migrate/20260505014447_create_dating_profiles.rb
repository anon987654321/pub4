# frozen_string_literal: true

class CreateDatingProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :dating_profiles do |t|
      t.references :user, null: false, foreign_key: true
      t.text :bio
      t.string :gender
      t.string :looking_for
      t.integer :age
      t.string :location
      t.decimal :latitude
      t.decimal :longitude
      t.boolean :visible

      t.timestamps
    end
  end
end
