# frozen_string_literal: true

class CreateTypingIndicators < ActiveRecord::Migration[8.1]
  def change
    create_table :typing_indicators do |t|
      t.references :conversation, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.datetime :expires_at

      t.timestamps
    end
  end
end
