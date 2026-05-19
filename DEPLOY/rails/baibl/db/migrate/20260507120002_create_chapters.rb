# frozen_string_literal: true

class CreateChapters < ActiveRecord::Migration[8.1]
  def change
    create_table :chapters do |t|
      t.references :book, foreign_key: true
      t.integer :number
      t.timestamps
    end
  end
end
