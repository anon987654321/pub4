# frozen_string_literal: true

class CreateTakeawayRestaurantsFts < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE VIRTUAL TABLE takeaway_restaurants_fts USING fts5(
        name, description, address, city, cuisine_type,
        content='takeaway_restaurants', content_rowid='id',
        tokenize='unicode61'
      );
      INSERT INTO takeaway_restaurants_fts(rowid, name, description, address, city, cuisine_type)
        SELECT id, name, COALESCE(description, ''), COALESCE(address, ''), COALESCE(city, ''), COALESCE(cuisine_type, '')
        FROM takeaway_restaurants;
      CREATE TRIGGER takeaway_restaurants_ai AFTER INSERT ON takeaway_restaurants BEGIN
        INSERT INTO takeaway_restaurants_fts(rowid, name, description, address, city, cuisine_type)
          VALUES (new.id, new.name, COALESCE(new.description, ''), COALESCE(new.address, ''), COALESCE(new.city, ''), COALESCE(new.cuisine_type, ''));
      END;
      CREATE TRIGGER takeaway_restaurants_au AFTER UPDATE ON takeaway_restaurants BEGIN
        INSERT INTO takeaway_restaurants_fts(takeaway_restaurants_fts, rowid, name, description, address, city, cuisine_type)
          VALUES ('delete', old.id, old.name, COALESCE(old.description, ''), COALESCE(old.address, ''), COALESCE(old.city, ''), COALESCE(old.cuisine_type, ''));
        INSERT INTO takeaway_restaurants_fts(rowid, name, description, address, city, cuisine_type)
          VALUES (new.id, new.name, COALESCE(new.description, ''), COALESCE(new.address, ''), COALESCE(new.city, ''), COALESCE(new.cuisine_type, ''));
      END;
      CREATE TRIGGER takeaway_restaurants_ad AFTER DELETE ON takeaway_restaurants BEGIN
        INSERT INTO takeaway_restaurants_fts(takeaway_restaurants_fts, rowid, name, description, address, city, cuisine_type)
          VALUES ('delete', old.id, old.name, COALESCE(old.description, ''), COALESCE(old.address, ''), COALESCE(old.city, ''), COALESCE(old.cuisine_type, ''));
      END;
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS takeaway_restaurants_ad"
    execute "DROP TRIGGER IF EXISTS takeaway_restaurants_au"
    execute "DROP TRIGGER IF EXISTS takeaway_restaurants_ai"
    execute "DROP TABLE IF EXISTS takeaway_restaurants_fts"
  end
end