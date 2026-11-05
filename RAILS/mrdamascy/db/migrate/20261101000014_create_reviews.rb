# frozen_string_literal: true

class CreateReviews < ActiveRecord::Migration[8.0]
  def change
    create_table :reviews do |t|
      t.references :order, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :rating, null: false
      t.text :body

      t.timestamps
    end
    add_index :reviews, [ :order_id, :user_id ], unique: true
  end
end
