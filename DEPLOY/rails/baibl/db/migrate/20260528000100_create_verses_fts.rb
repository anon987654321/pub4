# frozen_string_literal: true

class CreateVersesFts < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE VIRTUAL TABLE verses_fts USING fts5(
        content,
        content='verses', content_rowid='id',
        tokenize='unicode61'
      );
      INSERT INTO verses_fts(rowid, content) SELECT id, content FROM verses;
      CREATE TRIGGER verses_ai AFTER INSERT ON verses BEGIN
        INSERT INTO verses_fts(rowid, content) VALUES (new.id, new.content);
      END;
      CREATE TRIGGER verses_au AFTER UPDATE ON verses BEGIN
        INSERT INTO verses_fts(verses_fts, rowid, content)
          VALUES ('delete', old.id, old.content);
        INSERT INTO verses_fts(rowid, content) VALUES (new.id, new.content);
      END;
      CREATE TRIGGER verses_ad AFTER DELETE ON verses BEGIN
        INSERT INTO verses_fts(verses_fts, rowid, content)
          VALUES ('delete', old.id, old.content);
      END;
    SQL
  end

  def down
    execute "DROP TABLE IF EXISTS verses_fts"
    execute "DROP TRIGGER IF EXISTS verses_ai"
    execute "DROP TRIGGER IF EXISTS verses_au"
    execute "DROP TRIGGER IF EXISTS verses_ad"
  end
end
