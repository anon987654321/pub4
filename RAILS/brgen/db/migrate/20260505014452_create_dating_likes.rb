# frozen_string_literal: true

class CreateDatingLikes < ActiveRecord::Migration[8.1]
  def change
    create_table :dating_likes do |t|
      t.references :liker, null: false, foreign_key: true
      t.references :likee, null: false, foreign_key: true

      t.timestamps
    end
  end
end
