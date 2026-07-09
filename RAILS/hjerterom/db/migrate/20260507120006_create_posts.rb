# frozen_string_literal: true

class CreatePosts < ActiveRecord::Migration[8.1]
  def change
    create_table :posts do |t|
      t.references :user, foreign_key: true
      t.references :category, foreign_key: true
      t.string :title
      t.boolean :anonymous, default: false
      t.boolean :pinned, default: false
      t.integer :views_count, default: 0
      t.timestamps
    end
  end
end
