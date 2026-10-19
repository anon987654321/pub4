# frozen_string_literal: true

class AddScoreToPosts < ActiveRecord::Migration[8.1]
  def change
    add_column :posts, :score, :integer, null: false, default: 0
    add_index :posts, :score
  end
end
