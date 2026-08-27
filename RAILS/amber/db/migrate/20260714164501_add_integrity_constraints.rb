# frozen_string_literal: true

# Backfills + adds NOT NULL constraints that already exist as `validates
# presence:` in the models but were never enforced at the DB layer, adds a
# missing FK index, and deduplicates + adds unique composite indexes backing
# `validates uniqueness:` checks that are otherwise app-only (a real race
# under concurrent requests, e.g. two taps on "follow" landing at once).
class AddIntegrityConstraints < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE items SET title = 'Untitled item' WHERE title IS NULL"
    change_column_null :items, :title, false

    execute "UPDATE outfits SET name = 'Untitled outfit' WHERE name IS NULL"
    change_column_null :outfits, :name, false

    execute "UPDATE planned_outfits SET planned_date = date(created_at) WHERE planned_date IS NULL"
    change_column_null :planned_outfits, :planned_date, false

    execute "UPDATE posts SET body = '' WHERE body IS NULL"
    change_column_null :posts, :body, false

    add_index :comments, :parent_id unless index_exists?(:comments, :parent_id)

    dedup_and_unique_index :follows, %i[follower_id followee_id]
    dedup_and_unique_index :outfit_items, %i[item_id outfit_id]
    dedup_and_unique_index :planned_outfits, %i[user_id planned_date]
  end

  def down
    remove_index :planned_outfits, column: %i[user_id planned_date] if index_exists?(:planned_outfits, %i[user_id planned_date])
    remove_index :outfit_items, column: %i[item_id outfit_id] if index_exists?(:outfit_items, %i[item_id outfit_id])
    remove_index :follows, column: %i[follower_id followee_id] if index_exists?(:follows, %i[follower_id followee_id])
    remove_index :comments, :parent_id if index_exists?(:comments, :parent_id)

    change_column_null :posts, :body, true
    change_column_null :planned_outfits, :planned_date, true
    change_column_null :outfits, :name, true
    change_column_null :items, :title, true
  end

  private

  # Keeps the earliest row for each duplicate key and deletes the rest —
  # these are rows that already violated the model's own `validates
  # uniqueness:` scope, so they represent duplicate data the app never
  # intended to allow, not real divergent user records.
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
