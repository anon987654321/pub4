# frozen_string_literal: true

class CreateTagsFts < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE VIRTUAL TABLE tags_fts USING fts5(
        name,
        content='tags', content_rowid='id',
        tokenize='unicode61'
      );
      INSERT INTO tags_fts(rowid, name)
        SELECT id, name FROM tags;
      CREATE TRIGGER tags_ai AFTER INSERT ON tags BEGIN
        INSERT INTO tags_fts(rowid, name) VALUES (new.id, new.name);
      END;
      CREATE TRIGGER tags_au AFTER UPDATE ON tags BEGIN
        INSERT INTO tags_fts(tags_fts, rowid, name) VALUES ('delete', old.id, old.name);
        INSERT INTO tags_fts(rowid, name) VALUES (new.id, new.name);
      END;
      CREATE TRIGGER tags_ad AFTER DELETE ON tags BEGIN
        INSERT INTO tags_fts(tags_fts, rowid, name) VALUES ('delete', old.id, old.name);
      END;
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS tags_ad"
    execute "DROP TRIGGER IF EXISTS tags_au"
    execute "DROP TRIGGER IF EXISTS tags_ai"
    execute "DROP TABLE IF EXISTS tags_fts"
  end
end