# frozen_string_literal: true

class CreateTaggings < ActiveRecord::Migration[8.1]
  def change
    create_table :taggings do |t|
      t.references :post, foreign_key: true
      t.references :tag, foreign_key: true
      t.timestamps
    end
  end
end
