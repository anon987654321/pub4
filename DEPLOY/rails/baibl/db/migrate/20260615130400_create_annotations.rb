# frozen_string_literal: true

class CreateAnnotations < ActiveRecord::Migration[8.1]
  def change
    create_table :annotations do |t|
      t.references :verse, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.text :body, null: false
      t.integer :visibility, null: false, default: 0
      t.timestamps
    end
  end
end