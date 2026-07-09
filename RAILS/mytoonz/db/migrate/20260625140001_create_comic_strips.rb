# frozen_string_literal: true

class CreateComicStrips < ActiveRecord::Migration[8.1]
  def change
    create_table :comic_strips do |t|
      t.references :user, null: false, foreign_key: true
      t.text :prompt, null: false
      t.string :style, default: "comic", null: false
      t.string :status, default: "pending", null: false
      t.string :prediction_id
      t.json :image_urls

      t.timestamps
    end
  end
end