# frozen_string_literal: true

class CreateResourcesFts < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE VIRTUAL TABLE resources_fts USING fts5(
        title, description, resource_type,
        content='resources', content_rowid='id',
        tokenize='unicode61'
      );
      INSERT INTO resources_fts(rowid, title, description, resource_type)
        SELECT id, title, COALESCE(description, ''), COALESCE(resource_type, '') FROM resources;
      CREATE TRIGGER resources_ai AFTER INSERT ON resources BEGIN
        INSERT INTO resources_fts(rowid, title, description, resource_type)
          VALUES (new.id, new.title, COALESCE(new.description, ''), COALESCE(new.resource_type, ''));
      END;
      CREATE TRIGGER resources_au AFTER UPDATE ON resources BEGIN
        INSERT INTO resources_fts(resources_fts, rowid, title, description, resource_type)
          VALUES ('delete', old.id, old.title, COALESCE(old.description, ''), COALESCE(old.resource_type, ''));
        INSERT INTO resources_fts(rowid, title, description, resource_type)
          VALUES (new.id, new.title, COALESCE(new.description, ''), COALESCE(new.resource_type, ''));
      END;
      CREATE TRIGGER resources_ad AFTER DELETE ON resources BEGIN
        INSERT INTO resources_fts(resources_fts, rowid, title, description, resource_type)
          VALUES ('delete', old.id, old.title, COALESCE(old.description, ''), COALESCE(old.resource_type, ''));
      END;
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS resources_ad"
    execute "DROP TRIGGER IF EXISTS resources_au"
    execute "DROP TRIGGER IF EXISTS resources_ai"
    execute "DROP TABLE IF EXISTS resources_fts"
  end
end