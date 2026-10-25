# frozen_string_literal: true

class CreateShareDrafts < ActiveRecord::Migration[8.1]
  def change
    create_table :share_drafts do |t|
      t.references :user, null: false, foreign_key: true
      t.references :city, null: false, foreign_key: true
      t.string :title, null: false
      t.text :content
      t.datetime :expires_at, null: false
      t.timestamps
      t.index :expires_at
    end
  end
end
