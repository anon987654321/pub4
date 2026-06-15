# frozen_string_literal: true

class CreatePostsFts < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      CREATE VIRTUAL TABLE posts_fts USING fts5(
        title,
        content='posts',
        content_rowid='id'
      );
      INSERT INTO posts_fts(rowid, title)
        SELECT id, title FROM posts;
    SQL
  end

  def down
    execute "DROP TABLE IF EXISTS posts_fts"
  end
end