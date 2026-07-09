# frozen_string_literal: true

class CreatePosts < ActiveRecord::Migration[8.1]
  def change
    create_table :posts do |t|
      t.text :body
      t.references :user, null: false, foreign_key: true
      t.references :outfit, null: false, foreign_key: true
      t.references :item, null: false, foreign_key: true
      t.integer :likes_count

      t.timestamps
    end
  end
end
