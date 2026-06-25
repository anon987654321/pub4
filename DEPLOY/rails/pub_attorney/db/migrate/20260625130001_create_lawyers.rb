# frozen_string_literal: true

class CreateLawyers < ActiveRecord::Migration[8.1]
  def change
    create_table :lawyers do |t|
      t.string :name, null: false
      t.string :specialty
      t.string :bar_number
      t.text :bio
      t.decimal :rating, precision: 3, scale: 2, default: 0.0
      t.references :user, foreign_key: true

      t.timestamps
    end
  end
end