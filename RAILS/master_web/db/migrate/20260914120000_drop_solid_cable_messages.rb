# frozen_string_literal: true

# Solid Cable is gone: /events/stream is the face's one event pipe, so nothing
# writes or reads this table.
class DropSolidCableMessages < ActiveRecord::Migration[8.1]
  def up
    drop_table :solid_cable_messages, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
