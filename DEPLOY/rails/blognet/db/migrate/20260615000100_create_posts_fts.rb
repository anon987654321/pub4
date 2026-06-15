# frozen_string_literal: true

class CreatePostsFts < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE VIRTUAL TABLE posts_fts USING fts5(
        title, body,
        content='posts', content_rowid='id',
        tokenize='unicode61'
      );
      INSERT INTO posts_fts(rowid, title, body)
        SELECT p.id, p.title,
               COALESCE((SELECT body FROM action_text_rich_texts
                         WHERE record_type = 'Post' AND record_id = p.id AND name = 'body' LIMIT 1), '')
        FROM posts p;
      CREATE TRIGGER posts_ai AFTER INSERT ON posts BEGIN
        INSERT INTO posts_fts(rowid, title, body)
          VALUES (new.id, new.title, '');
      END;
      CREATE TRIGGER posts_au AFTER UPDATE ON posts BEGIN
        INSERT INTO posts_fts(posts_fts, rowid, title, body)
          VALUES ('delete', old.id, old.title, COALESCE((SELECT body FROM action_text_rich_texts
                    WHERE record_type = 'Post' AND record_id = old.id AND name = 'body' LIMIT 1), ''));
        INSERT INTO posts_fts(rowid, title, body)
          VALUES (new.id, new.title, COALESCE((SELECT body FROM action_text_rich_texts
                    WHERE record_type = 'Post' AND record_id = new.id AND name = 'body' LIMIT 1), ''));
      END;
      CREATE TRIGGER posts_ad AFTER DELETE ON posts BEGIN
        INSERT INTO posts_fts(posts_fts, rowid, title, body)
          VALUES ('delete', old.id, old.title, COALESCE((SELECT body FROM action_text_rich_texts
                    WHERE record_type = 'Post' AND record_id = old.id AND name = 'body' LIMIT 1), ''));
      END;
      CREATE TRIGGER action_text_posts_au AFTER UPDATE ON action_text_rich_texts
        WHEN new.record_type = 'Post' AND new.name = 'body' BEGIN
        INSERT INTO posts_fts(posts_fts, rowid, title, body)
          SELECT 'delete', p.id, p.title, old.body FROM posts p WHERE p.id = new.record_id;
        INSERT INTO posts_fts(rowid, title, body)
          SELECT p.id, p.title, new.body FROM posts p WHERE p.id = new.record_id;
      END;
      CREATE TRIGGER action_text_posts_ai AFTER INSERT ON action_text_rich_texts
        WHEN new.record_type = 'Post' AND new.name = 'body' BEGIN
        INSERT INTO posts_fts(posts_fts, rowid, title, body)
          SELECT 'delete', p.id, p.title, '' FROM posts p WHERE p.id = new.record_id;
        INSERT INTO posts_fts(rowid, title, body)
          SELECT p.id, p.title, new.body FROM posts p WHERE p.id = new.record_id;
      END;
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS action_text_posts_ai"
    execute "DROP TRIGGER IF EXISTS action_text_posts_au"
    execute "DROP TRIGGER IF EXISTS posts_ad"
    execute "DROP TRIGGER IF EXISTS posts_au"
    execute "DROP TRIGGER IF EXISTS posts_ai"
    execute "DROP TABLE IF EXISTS posts_fts"
  end
end