# frozen_string_literal: true

class CreateFollows < ActiveRecord::Migration[8.1]
  def change
    create_table :follows do |t|
      t.integer :follower_id
      t.integer :followed_id

      t.timestamps
    end
    add_index :follows, :follower_id
    add_index :follows, :followed_id
  end
end
