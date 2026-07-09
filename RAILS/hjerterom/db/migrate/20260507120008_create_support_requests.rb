# frozen_string_literal: true

class CreateSupportRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :support_requests do |t|
      t.references :user, foreign_key: true
      t.string :subject
      t.string :status
      t.string :priority
      t.datetime :resolved_at
      t.timestamps
    end
  end
end
