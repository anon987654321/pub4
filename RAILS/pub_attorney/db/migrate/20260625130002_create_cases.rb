# frozen_string_literal: true

class CreateCases < ActiveRecord::Migration[8.1]
  def change
    create_table :cases do |t|
      t.string :title, null: false
      t.text :description
      t.string :status, default: "open", null: false
      t.string :category
      t.references :user, null: false, foreign_key: true
      t.references :lawyer, foreign_key: true

      t.timestamps
    end
  end
end