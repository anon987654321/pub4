# frozen_string_literal: true

# Backfills + adds NOT NULL constraints that already exist as `validates
# presence:` in the models but were never enforced at the DB layer, adds a
# missing FK index, and deduplicates + adds unique composite indexes backing
# `validates uniqueness:` checks that were previously app-only (a real race
# under concurrent requests, e.g. two taps on "watch" landing at once).
class AddIntegrityConstraints < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE categories SET name = 'Untitled category' WHERE name IS NULL"
    change_column_null :categories, :name, false

    execute "UPDATE comments SET content = '' WHERE content IS NULL"
    change_column_null :comments, :content, false

    execute "UPDATE ports SET name = 'unnamed-' || id WHERE name IS NULL"
    change_column_null :ports, :name, false

    execute "UPDATE port_updates SET new_version = 'unknown' WHERE new_version IS NULL"
    change_column_null :port_updates, :new_version, false

    add_index :comments, :parent_id unless index_exists?(:comments, :parent_id)

    dedup_and_unique_index :dependencies, %i[port_id depends_on_id dep_type]
    dedup_and_unique_index :watches, %i[user_id port_id]
  end

  def down
    remove_index :watches, column: %i[user_id port_id] if index_exists?(:watches, %i[user_id port_id])
    remove_index :dependencies, column: %i[port_id depends_on_id dep_type] if index_exists?(:dependencies, %i[port_id depends_on_id dep_type])
    remove_index :comments, :parent_id if index_exists?(:comments, :parent_id)

    change_column_null :port_updates, :new_version, true
    change_column_null :ports, :name, true
    change_column_null :comments, :content, true
    change_column_null :categories, :name, true
  end

  private

  # Keeps the earliest row for each duplicate key and deletes the rest —
  # these are rows that already violated the model's own `validates
  # uniqueness:` scope, so they represent duplicate data the app never
  # intended to allow.
  def dedup_and_unique_index(table, columns)
    return if index_exists?(table, columns, unique: true)

    cols = columns.join(", ")
    execute <<~SQL.squish
      DELETE FROM #{table}
      WHERE id NOT IN (
        SELECT MIN(id) FROM #{table} GROUP BY #{cols}
      )
    SQL
    add_index table, columns, unique: true
  end
end
