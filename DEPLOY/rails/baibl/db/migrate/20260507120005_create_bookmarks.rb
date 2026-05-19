# frozen_string_literal: true

class CreateBookmarks < ActiveRecord::Migration[8.1]
  def change
    create_table :bookmarks do |t|
      t.references :verse, foreign_key: true
      t.references :user, foreign_key: true
      t.text :note
      t.timestamps
    end
  end
end
