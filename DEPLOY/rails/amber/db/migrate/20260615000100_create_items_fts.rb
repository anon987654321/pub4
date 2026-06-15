# frozen_string_literal: true

class CreateItemsFts < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE VIRTUAL TABLE items_fts USING fts5(
        title, category, color, material, brand, season, occasion_tags,
        content='items', content_rowid='id',
        tokenize='unicode61'
      );
      INSERT INTO items_fts(rowid, title, category, color, material, brand, season, occasion_tags)
        SELECT id, title, COALESCE(category, ''), COALESCE(color, ''), COALESCE(material, ''),
               COALESCE(brand, ''), COALESCE(season, ''), COALESCE(occasion_tags, '')
        FROM items;
      CREATE TRIGGER items_ai AFTER INSERT ON items BEGIN
        INSERT INTO items_fts(rowid, title, category, color, material, brand, season, occasion_tags)
          VALUES (new.id, new.title, COALESCE(new.category, ''), COALESCE(new.color, ''), COALESCE(new.material, ''),
                  COALESCE(new.brand, ''), COALESCE(new.season, ''), COALESCE(new.occasion_tags, ''));
      END;
      CREATE TRIGGER items_au AFTER UPDATE ON items BEGIN
        INSERT INTO items_fts(items_fts, rowid, title, category, color, material, brand, season, occasion_tags)
          VALUES ('delete', old.id, old.title, COALESCE(old.category, ''), COALESCE(old.color, ''), COALESCE(old.material, ''),
                  COALESCE(old.brand, ''), COALESCE(old.season, ''), COALESCE(old.occasion_tags, ''));
        INSERT INTO items_fts(rowid, title, category, color, material, brand, season, occasion_tags)
          VALUES (new.id, new.title, COALESCE(new.category, ''), COALESCE(new.color, ''), COALESCE(new.material, ''),
                  COALESCE(new.brand, ''), COALESCE(new.season, ''), COALESCE(new.occasion_tags, ''));
      END;
      CREATE TRIGGER items_ad AFTER DELETE ON items BEGIN
        INSERT INTO items_fts(items_fts, rowid, title, category, color, material, brand, season, occasion_tags)
          VALUES ('delete', old.id, old.title, COALESCE(old.category, ''), COALESCE(old.color, ''), COALESCE(old.material, ''),
                  COALESCE(old.brand, ''), COALESCE(old.season, ''), COALESCE(old.occasion_tags, ''));
      END;
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS items_ad"
    execute "DROP TRIGGER IF EXISTS items_au"
    execute "DROP TRIGGER IF EXISTS items_ai"
    execute "DROP TABLE IF EXISTS items_fts"
  end
end