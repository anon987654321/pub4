# frozen_string_literal: true

class CreatePortsFts < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE VIRTUAL TABLE ports_fts USING fts5(
        name, comment,
        content='ports', content_rowid='id',
        tokenize='unicode61'
      );
      INSERT INTO ports_fts(rowid, name, comment)
        SELECT id, name, COALESCE(comment, '') FROM ports;
      CREATE TRIGGER ports_ai AFTER INSERT ON ports BEGIN
        INSERT INTO ports_fts(rowid, name, comment)
          VALUES (new.id, new.name, COALESCE(new.comment, ''));
      END;
      CREATE TRIGGER ports_au AFTER UPDATE ON ports BEGIN
        INSERT INTO ports_fts(ports_fts, rowid, name, comment)
          VALUES ('delete', old.id, old.name, COALESCE(old.comment, ''));
        INSERT INTO ports_fts(rowid, name, comment)
          VALUES (new.id, new.name, COALESCE(new.comment, ''));
      END;
      CREATE TRIGGER ports_ad AFTER DELETE ON ports BEGIN
        INSERT INTO ports_fts(ports_fts, rowid, name, comment)
          VALUES ('delete', old.id, old.name, COALESCE(old.comment, ''));
      END;
    SQL
  end

  def down
    execute "DROP TABLE IF EXISTS ports_fts"
    execute "DROP TRIGGER IF EXISTS ports_ai"
    execute "DROP TRIGGER IF EXISTS ports_au"
    execute "DROP TRIGGER IF EXISTS ports_ad"
  end
end
