# frozen_string_literal: true

class CreatePlacesFts < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE VIRTUAL TABLE places_fts USING fts5(
        name, kind,
        content='places', content_rowid='id',
        tokenize='unicode61'
      );
      INSERT INTO places_fts(rowid, name, kind)
        SELECT id, name, COALESCE(kind, '') FROM places;
      CREATE TRIGGER places_ai AFTER INSERT ON places BEGIN
        INSERT INTO places_fts(rowid, name, kind)
          VALUES (new.id, new.name, COALESCE(new.kind, ''));
      END;
      CREATE TRIGGER places_au AFTER UPDATE ON places BEGIN
        INSERT INTO places_fts(places_fts, rowid, name, kind)
          VALUES ('delete', old.id, old.name, COALESCE(old.kind, ''));
        INSERT INTO places_fts(rowid, name, kind)
          VALUES (new.id, new.name, COALESCE(new.kind, ''));
      END;
      CREATE TRIGGER places_ad AFTER DELETE ON places BEGIN
        INSERT INTO places_fts(places_fts, rowid, name, kind)
          VALUES ('delete', old.id, old.name, COALESCE(old.kind, ''));
      END;
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS places_ad"
    execute "DROP TRIGGER IF EXISTS places_au"
    execute "DROP TRIGGER IF EXISTS places_ai"
    execute "DROP TABLE IF EXISTS places_fts"
  end
end