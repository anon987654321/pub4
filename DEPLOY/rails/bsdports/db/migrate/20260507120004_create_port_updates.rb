# frozen_string_literal: true

class CreatePortUpdates < ActiveRecord::Migration[8.1]
  def change
    create_table :port_updates do |t|
      t.references :port, foreign_key: true
      t.string :old_version
      t.string :new_version
      t.string :commit_id
      t.text :commit_message
      t.datetime :committed_at
      t.timestamps
    end
  end
end
