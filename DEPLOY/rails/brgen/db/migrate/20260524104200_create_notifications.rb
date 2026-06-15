# frozen_string_literal: true

class CreateNotifications < ActiveRecord::Migration[8.1]
  def change
    return if table_exists?(:notifications)

    create_table :notifications do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.text :body
      t.string :source_type
      t.integer :source_id
      t.datetime :read_at
      t.timestamps
    end

    add_index :notifications, %i[user_id read_at]
    add_index :notifications, %i[source_type source_id]
  end
end
