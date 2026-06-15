# frozen_string_literal: true

class CreateOutfitsFts < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE VIRTUAL TABLE outfits_fts USING fts5(
        name, description, category, season, occasion, item_names,
        content='outfits', content_rowid='id',
        tokenize='unicode61'
      );
      INSERT INTO outfits_fts(rowid, name, description, category, season, occasion, item_names)
        SELECT o.id, o.name, COALESCE(o.description, ''), COALESCE(o.category, ''), COALESCE(o.season, ''),
               COALESCE(o.occasion, ''),
               COALESCE((SELECT group_concat(i.title, ' ') FROM items i
                         INNER JOIN outfit_items oi ON oi.item_id = i.id
                         WHERE oi.outfit_id = o.id), '')
        FROM outfits o;
      CREATE TRIGGER outfits_ai AFTER INSERT ON outfits BEGIN
        INSERT INTO outfits_fts(rowid, name, description, category, season, occasion, item_names)
          VALUES (new.id, new.name, COALESCE(new.description, ''), COALESCE(new.category, ''), COALESCE(new.season, ''),
                  COALESCE(new.occasion, ''), '');
      END;
      CREATE TRIGGER outfits_au AFTER UPDATE ON outfits BEGIN
        INSERT INTO outfits_fts(outfits_fts, rowid, name, description, category, season, occasion, item_names)
          VALUES ('delete', old.id, old.name, COALESCE(old.description, ''), COALESCE(old.category, ''), COALESCE(old.season, ''),
                  COALESCE(old.occasion, ''), '');
        INSERT INTO outfits_fts(rowid, name, description, category, season, occasion, item_names)
          VALUES (new.id, new.name, COALESCE(new.description, ''), COALESCE(new.category, ''), COALESCE(new.season, ''),
                  COALESCE(new.occasion, ''), '');
      END;
      CREATE TRIGGER outfits_ad AFTER DELETE ON outfits BEGIN
        INSERT INTO outfits_fts(outfits_fts, rowid, name, description, category, season, occasion, item_names)
          VALUES ('delete', old.id, old.name, COALESCE(old.description, ''), COALESCE(old.category, ''), COALESCE(old.season, ''),
                  COALESCE(old.occasion, ''), '');
      END;
      CREATE TRIGGER outfit_items_ai AFTER INSERT ON outfit_items BEGIN
        INSERT INTO outfits_fts(outfits_fts, rowid, name, description, category, season, occasion, item_names)
          SELECT 'delete', o.id, o.name, COALESCE(o.description, ''), COALESCE(o.category, ''), COALESCE(o.season, ''),
                 COALESCE(o.occasion, ''), COALESCE((SELECT group_concat(i.title, ' ') FROM items i
                   INNER JOIN outfit_items oi ON oi.item_id = i.id WHERE oi.outfit_id = o.id), '')
          FROM outfits o WHERE o.id = new.outfit_id;
        INSERT INTO outfits_fts(rowid, name, description, category, season, occasion, item_names)
          SELECT o.id, o.name, COALESCE(o.description, ''), COALESCE(o.category, ''), COALESCE(o.season, ''),
                 COALESCE(o.occasion, ''),
                 COALESCE((SELECT group_concat(i.title, ' ') FROM items i
                   INNER JOIN outfit_items oi ON oi.item_id = i.id WHERE oi.outfit_id = o.id), '')
          FROM outfits o WHERE o.id = new.outfit_id;
      END;
      CREATE TRIGGER outfit_items_ad AFTER DELETE ON outfit_items BEGIN
        INSERT INTO outfits_fts(outfits_fts, rowid, name, description, category, season, occasion, item_names)
          SELECT 'delete', o.id, o.name, COALESCE(o.description, ''), COALESCE(o.category, ''), COALESCE(o.season, ''),
                 COALESCE(o.occasion, ''), COALESCE((SELECT group_concat(i.title, ' ') FROM items i
                   INNER JOIN outfit_items oi ON oi.item_id = i.id WHERE oi.outfit_id = o.id), '')
          FROM outfits o WHERE o.id = old.outfit_id;
        INSERT INTO outfits_fts(rowid, name, description, category, season, occasion, item_names)
          SELECT o.id, o.name, COALESCE(o.description, ''), COALESCE(o.category, ''), COALESCE(o.season, ''),
                 COALESCE(o.occasion, ''),
                 COALESCE((SELECT group_concat(i.title, ' ') FROM items i
                   INNER JOIN outfit_items oi ON oi.item_id = i.id WHERE oi.outfit_id = o.id), '')
          FROM outfits o WHERE o.id = old.outfit_id;
      END;
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS outfit_items_ad"
    execute "DROP TRIGGER IF EXISTS outfit_items_ai"
    execute "DROP TRIGGER IF EXISTS outfits_ad"
    execute "DROP TRIGGER IF EXISTS outfits_au"
    execute "DROP TRIGGER IF EXISTS outfits_ai"
    execute "DROP TABLE IF EXISTS outfits_fts"
  end
end