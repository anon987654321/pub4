# frozen_string_literal: true

class CreateTvChannelsFts < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE VIRTUAL TABLE tv_channels_fts USING fts5(
        name, description,
        content='tv_channels', content_rowid='id',
        tokenize='unicode61'
      );
      INSERT INTO tv_channels_fts(rowid, name, description)
        SELECT id, name, COALESCE(description, '') FROM tv_channels;
      CREATE TRIGGER tv_channels_ai AFTER INSERT ON tv_channels BEGIN
        INSERT INTO tv_channels_fts(rowid, name, description)
          VALUES (new.id, new.name, COALESCE(new.description, ''));
      END;
      CREATE TRIGGER tv_channels_au AFTER UPDATE ON tv_channels BEGIN
        INSERT INTO tv_channels_fts(tv_channels_fts, rowid, name, description)
          VALUES ('delete', old.id, old.name, COALESCE(old.description, ''));
        INSERT INTO tv_channels_fts(rowid, name, description)
          VALUES (new.id, new.name, COALESCE(new.description, ''));
      END;
      CREATE TRIGGER tv_channels_ad AFTER DELETE ON tv_channels BEGIN
        INSERT INTO tv_channels_fts(tv_channels_fts, rowid, name, description)
          VALUES ('delete', old.id, old.name, COALESCE(old.description, ''));
      END;
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS tv_channels_ad"
    execute "DROP TRIGGER IF EXISTS tv_channels_au"
    execute "DROP TRIGGER IF EXISTS tv_channels_ai"
    execute "DROP TABLE IF EXISTS tv_channels_fts"
  end
end