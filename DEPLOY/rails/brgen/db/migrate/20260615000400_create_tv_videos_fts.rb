# frozen_string_literal: true

class CreateTvVideosFts < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE VIRTUAL TABLE tv_videos_fts USING fts5(
        title, description,
        content='tv_videos', content_rowid='id',
        tokenize='unicode61'
      );
      INSERT INTO tv_videos_fts(rowid, title, description)
        SELECT id, title, COALESCE(description, '') FROM tv_videos;
      CREATE TRIGGER tv_videos_ai AFTER INSERT ON tv_videos BEGIN
        INSERT INTO tv_videos_fts(rowid, title, description)
          VALUES (new.id, new.title, COALESCE(new.description, ''));
      END;
      CREATE TRIGGER tv_videos_au AFTER UPDATE ON tv_videos BEGIN
        INSERT INTO tv_videos_fts(tv_videos_fts, rowid, title, description)
          VALUES ('delete', old.id, old.title, COALESCE(old.description, ''));
        INSERT INTO tv_videos_fts(rowid, title, description)
          VALUES (new.id, new.title, COALESCE(new.description, ''));
      END;
      CREATE TRIGGER tv_videos_ad AFTER DELETE ON tv_videos BEGIN
        INSERT INTO tv_videos_fts(tv_videos_fts, rowid, title, description)
          VALUES ('delete', old.id, old.title, COALESCE(old.description, ''));
      END;
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS tv_videos_ad"
    execute "DROP TRIGGER IF EXISTS tv_videos_au"
    execute "DROP TRIGGER IF EXISTS tv_videos_ai"
    execute "DROP TABLE IF EXISTS tv_videos_fts"
  end
end