# frozen_string_literal: true

class CreateFoodListingsFts < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE VIRTUAL TABLE food_listings_fts USING fts5(
        title, description, city, dietary_info,
        content='food_listings', content_rowid='id',
        tokenize='unicode61'
      );
      INSERT INTO food_listings_fts(rowid, title, description, city, dietary_info)
        SELECT id, title, COALESCE(description, ''), COALESCE(city, ''), COALESCE(dietary_info, '')
        FROM food_listings;
      CREATE TRIGGER food_listings_ai AFTER INSERT ON food_listings BEGIN
        INSERT INTO food_listings_fts(rowid, title, description, city, dietary_info)
          VALUES (new.id, new.title, COALESCE(new.description, ''), COALESCE(new.city, ''), COALESCE(new.dietary_info, ''));
      END;
      CREATE TRIGGER food_listings_au AFTER UPDATE ON food_listings BEGIN
        INSERT INTO food_listings_fts(food_listings_fts, rowid, title, description, city, dietary_info)
          VALUES ('delete', old.id, old.title, COALESCE(old.description, ''), COALESCE(old.city, ''), COALESCE(old.dietary_info, ''));
        INSERT INTO food_listings_fts(rowid, title, description, city, dietary_info)
          VALUES (new.id, new.title, COALESCE(new.description, ''), COALESCE(new.city, ''), COALESCE(new.dietary_info, ''));
      END;
      CREATE TRIGGER food_listings_ad AFTER DELETE ON food_listings BEGIN
        INSERT INTO food_listings_fts(food_listings_fts, rowid, title, description, city, dietary_info)
          VALUES ('delete', old.id, old.title, COALESCE(old.description, ''), COALESCE(old.city, ''), COALESCE(old.dietary_info, ''));
      END;
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS food_listings_ad"
    execute "DROP TRIGGER IF EXISTS food_listings_au"
    execute "DROP TRIGGER IF EXISTS food_listings_ai"
    execute "DROP TABLE IF EXISTS food_listings_fts"
  end
end