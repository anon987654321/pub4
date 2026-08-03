# frozen_string_literal: true

# User blocking: a blocker never sees the blocked user's posts, comments, or DMs.
# Silent (no notification), mirroring how Follow is modelled minus the emit hooks.
class CreateBlocks < ActiveRecord::Migration[8.1]
  def change
    create_table :blocks do |t|
      t.references :blocker, null: false, foreign_key: { to_table: :users }
      t.references :blocked, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :blocks, %i[blocker_id blocked_id], unique: true
  end
end
