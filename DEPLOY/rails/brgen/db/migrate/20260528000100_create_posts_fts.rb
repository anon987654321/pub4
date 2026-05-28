# frozen_string_literal: true

class CreatePostsFts < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE VIRTUAL TABLE posts_fts USING fts5(
        title, content,
        content='posts', content_rowid='id',
        tokenize='unicode61'
      );
      INSERT INTO posts_fts(rowid, title, content)
        SELECT id, title, COALESCE(content, '') FROM posts;
      CREATE TRIGGER posts_ai AFTER INSERT ON posts BEGIN
        INSERT INTO posts_fts(rowid, title, content)
          VALUES (new.id, new.title, COALESCE(new.content, ''));
      END;
      CREATE TRIGGER posts_au AFTER UPDATE ON posts BEGIN
        INSERT INTO posts_fts(posts_fts, rowid, title, content)
          VALUES ('delete', old.id, old.title, COALESCE(old.content, ''));
        INSERT INTO posts_fts(rowid, title, content)
          VALUES (new.id, new.title, COALESCE(new.content, ''));
      END;
      CREATE TRIGGER posts_ad AFTER DELETE ON posts BEGIN
        INSERT INTO posts_fts(posts_fts, rowid, title, content)
          VALUES ('delete', old.id, old.title, COALESCE(old.content, ''));
      END;
    SQL
  end

  def down
    execute "DROP TABLE IF EXISTS posts_fts"
    execute "DROP TRIGGER IF EXISTS posts_ai"
    execute "DROP TRIGGER IF EXISTS posts_au"
    execute "DROP TRIGGER IF EXISTS posts_ad"
  end
end
