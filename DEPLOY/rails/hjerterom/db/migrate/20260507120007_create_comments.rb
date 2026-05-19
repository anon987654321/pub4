# frozen_string_literal: true

class CreateComments < ActiveRecord::Migration[8.1]
  def change
    create_table :comments do |t|
      t.references :user, foreign_key: true
      t.references :post, foreign_key: true
      t.integer :parent_id
      t.text :content
      t.boolean :anonymous, default: false
      t.timestamps
    end
  end
end
