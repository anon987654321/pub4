# frozen_string_literal: true

class CreateStreams < ActiveRecord::Migration[8.1]
  def change
    create_table :streams do |t|
      t.string :content_type
      t.string :url
      t.references :user, null: false, foreign_key: true
      t.references :post, null: false, foreign_key: true
      t.integer :duration

      t.timestamps
    end
  end
end
