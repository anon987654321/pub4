# frozen_string_literal: true

class CreateVotes < ActiveRecord::Migration[8.1]
  def change
    create_table :votes do |t|
      t.integer :value
      t.references :user, null: false, foreign_key: true
      t.references :votable, polymorphic: true, null: false

      t.timestamps
    end
  end
end
