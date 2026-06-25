# frozen_string_literal: true

class CreateComments < ActiveRecord::Migration[8.1]
  def change
    create_table :comments do |t|
      t.references :video, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :content, null: false

      t.timestamps
    end
  end
end