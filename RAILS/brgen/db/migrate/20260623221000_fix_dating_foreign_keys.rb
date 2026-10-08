# frozen_string_literal: true

class FixDatingForeignKeys < ActiveRecord::Migration[8.1]
  def up
    execute 'PRAGMA foreign_keys = OFF'
    rebuild_likes
    rebuild_dislikes
    rebuild_matches
    execute 'PRAGMA foreign_keys = ON'
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def rebuild_likes
    return unless table_exists?(:dating_likes)

    rename_table :dating_likes, :dating_likes_legacy
    create_table :dating_likes do |t|
      t.references :liker, null: false, foreign_key: { to_table: :users }
      t.references :likee, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end
    execute <<~SQL.squish
      INSERT INTO dating_likes (id, liker_id, likee_id, created_at, updated_at)
      SELECT id, liker_id, likee_id, created_at, updated_at FROM dating_likes_legacy
    SQL
    drop_table :dating_likes_legacy
  end

  def rebuild_dislikes
    return unless table_exists?(:dating_dislikes)

    rename_table :dating_dislikes, :dating_dislikes_legacy
    create_table :dating_dislikes do |t|
      t.references :disliker, null: false, foreign_key: { to_table: :users }
      t.references :dislikee, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end
    execute <<~SQL.squish
      INSERT INTO dating_dislikes (id, disliker_id, dislikee_id, created_at, updated_at)
      SELECT id, disliker_id, dislikee_id, created_at, updated_at FROM dating_dislikes_legacy
    SQL
    drop_table :dating_dislikes_legacy
  end

  def rebuild_matches
    return unless table_exists?(:dating_matches)

    rename_table :dating_matches, :dating_matches_legacy
    create_table :dating_matches do |t|
      t.references :initiator, null: false, foreign_key: { to_table: :users }
      t.references :receiver, null: false, foreign_key: { to_table: :users }
      t.string :status
      t.timestamps
    end
    execute <<~SQL.squish
      INSERT INTO dating_matches (id, initiator_id, receiver_id, status, created_at, updated_at)
      SELECT id, initiator_id, receiver_id, status, created_at, updated_at FROM dating_matches_legacy
    SQL
    drop_table :dating_matches_legacy
  end
end
