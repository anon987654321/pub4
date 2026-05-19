# frozen_string_literal: true

class CreateFollows < ActiveRecord::Migration[8.1]
  def change
    create_table :follows do |t|
      t.references :follower, null: false, foreign_key: true
      t.references :followee, null: false, foreign_key: true

      t.timestamps
    end
  end
end
