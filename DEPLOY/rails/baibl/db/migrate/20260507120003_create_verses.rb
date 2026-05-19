# frozen_string_literal: true

class CreateVerses < ActiveRecord::Migration[8.1]
  def change
    create_table :verses do |t|
      t.references :chapter, foreign_key: true
      t.references :book, foreign_key: true
      t.integer :number
      t.text :content
      t.timestamps
    end
  end
end
