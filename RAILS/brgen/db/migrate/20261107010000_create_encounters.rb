# frozen_string_literal: true

# Chatroulette-style pairing queue: one row per ask, waiting -> matched ->
# closed. partner_id is the stranger the row paired with; conversation_id is
# the direct conversation the pair landed in.
class CreateEncounters < ActiveRecord::Migration[8.2]
  def change
    create_table :encounters do |t|
      t.references :user, null: false, foreign_key: true
      t.references :partner, foreign_key: { to_table: :users }
      t.references :conversation, foreign_key: true
      t.string :status, null: false, default: "waiting"
      t.timestamps
    end
    add_index :encounters, [:status, :created_at]
  end
end
