# frozen_string_literal: true

class CreateComments < ActiveRecord::Migration[8.1]
  def change
    create_table :comments do |t|
      t.text :content, null: false
      t.references :user, null: false, foreign_key: true
      t.references :commentable, polymorphic: true, null: false
      t.integer :parent_id

      t.timestamps
    end
  end
end
