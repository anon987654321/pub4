# frozen_string_literal: true

class CreatePlaylistSetsFts < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE VIRTUAL TABLE playlist_sets_fts USING fts5(
        name, description,
        content='playlist_sets', content_rowid='id',
        tokenize='unicode61'
      );
      INSERT INTO playlist_sets_fts(rowid, name, description)
        SELECT id, name, COALESCE(description, '') FROM playlist_sets;
      CREATE TRIGGER playlist_sets_ai AFTER INSERT ON playlist_sets BEGIN
        INSERT INTO playlist_sets_fts(rowid, name, description)
          VALUES (new.id, new.name, COALESCE(new.description, ''));
      END;
      CREATE TRIGGER playlist_sets_au AFTER UPDATE ON playlist_sets BEGIN
        INSERT INTO playlist_sets_fts(playlist_sets_fts, rowid, name, description)
          VALUES ('delete', old.id, old.name, COALESCE(old.description, ''));
        INSERT INTO playlist_sets_fts(rowid, name, description)
          VALUES (new.id, new.name, COALESCE(new.description, ''));
      END;
      CREATE TRIGGER playlist_sets_ad AFTER DELETE ON playlist_sets BEGIN
        INSERT INTO playlist_sets_fts(playlist_sets_fts, rowid, name, description)
          VALUES ('delete', old.id, old.name, COALESCE(old.description, ''));
      END;
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS playlist_sets_ad"
    execute "DROP TRIGGER IF EXISTS playlist_sets_au"
    execute "DROP TRIGGER IF EXISTS playlist_sets_ai"
    execute "DROP TABLE IF EXISTS playlist_sets_fts"
  end
end