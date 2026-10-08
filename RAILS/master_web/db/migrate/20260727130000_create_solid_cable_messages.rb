# frozen_string_literal: true

# MASTER/web had no migrations and no db/schema.rb at all, while config/cable.yml
# selects `adapter: solid_cable` for both development and production. Solid Cable
# is database-backed, so every ActionCable broadcast on ai.brgen.no was writing to
# a table that does not exist. Nothing caught it because:
#
#   * test env uses `adapter: test`, so the cable path is never exercised there;
#   * and the four Ruby test files could not run at all — without a schema.rb,
#     maintain_test_schema aborts the whole suite before the first test.
#
# Columns and indexes are copied from the gem's own installer template
# (solid_cable-3.0.12 lib/generators/solid_cable/install/templates/db/cable_schema.rb)
# rather than invented. Note `created_at` only — Solid Cable has no updated_at,
# so this deliberately does not use t.timestamps.
#
# cable.yml declares no `connects_to`, so Solid Cable uses the primary database
# and the table belongs in the primary schema.
class CreateSolidCableMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :solid_cable_messages do |t|
      t.binary :channel, limit: 1024, null: false
      t.binary :payload, limit: 536_870_912, null: false
      t.datetime :created_at, null: false
      t.integer :channel_hash, limit: 8, null: false
    end

    add_index :solid_cable_messages, :channel
    add_index :solid_cable_messages, :channel_hash
    add_index :solid_cable_messages, :created_at
  end
end
