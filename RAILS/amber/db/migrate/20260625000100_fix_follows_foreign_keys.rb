# frozen_string_literal: true

class FixFollowsForeignKeys < ActiveRecord::Migration[8.1]
  def up
    return unless table_exists?(:follows)

    if sqlite?
      rebuild_follows_without_phantom_keys
    else
      drop_phantom_keys
      add_user_keys
    end
  end

  def down
    return unless table_exists?(:follows)

    remove_foreign_key :follows, column: :follower_id if foreign_key_exists?(:follows, column: :follower_id)
    remove_foreign_key :follows, column: :followee_id if foreign_key_exists?(:follows, column: :followee_id)
  end

  private

  def sqlite?
    connection.adapter_name.match?(/SQLite/i)
  end

  def rebuild_follows_without_phantom_keys
    execute "PRAGMA foreign_keys=OFF"
    create_table :follows_fixed, id: :integer do |t|
      t.integer :followee_id, null: false
      t.integer :follower_id, null: false
      t.timestamps
    end
    execute <<~SQL.squish
      INSERT INTO follows_fixed (id, followee_id, follower_id, created_at, updated_at)
      SELECT id, followee_id, follower_id, created_at, updated_at FROM follows
    SQL
    drop_table :follows
    rename_table :follows_fixed, :follows
    add_index :follows, :followee_id unless index_exists?(:follows, :followee_id)
    add_index :follows, :follower_id unless index_exists?(:follows, :follower_id)
    execute "PRAGMA foreign_keys=ON"
    add_user_keys
  end

  def drop_phantom_keys
    remove_foreign_key :follows, column: :follower_id if foreign_key_exists?(:follows, column: :follower_id)
    remove_foreign_key :follows, column: :followee_id if foreign_key_exists?(:follows, column: :followee_id)
  end

  def add_user_keys
    add_foreign_key :follows, :users, column: :follower_id unless foreign_key_exists?(:follows, column: :follower_id)
    add_foreign_key :follows, :users, column: :followee_id unless foreign_key_exists?(:follows, column: :followee_id)
  end
end
