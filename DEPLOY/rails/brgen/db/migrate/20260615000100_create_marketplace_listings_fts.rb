# frozen_string_literal: true

class CreateMarketplaceListingsFts < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE VIRTUAL TABLE marketplace_listings_fts USING fts5(
        title, description, location,
        content='marketplace_listings', content_rowid='id',
        tokenize='unicode61'
      );
      INSERT INTO marketplace_listings_fts(rowid, title, description, location)
        SELECT id, title, COALESCE(description, ''), COALESCE(location, '') FROM marketplace_listings;
      CREATE TRIGGER marketplace_listings_ai AFTER INSERT ON marketplace_listings BEGIN
        INSERT INTO marketplace_listings_fts(rowid, title, description, location)
          VALUES (new.id, new.title, COALESCE(new.description, ''), COALESCE(new.location, ''));
      END;
      CREATE TRIGGER marketplace_listings_au AFTER UPDATE ON marketplace_listings BEGIN
        INSERT INTO marketplace_listings_fts(marketplace_listings_fts, rowid, title, description, location)
          VALUES ('delete', old.id, old.title, COALESCE(old.description, ''), COALESCE(old.location, ''));
        INSERT INTO marketplace_listings_fts(rowid, title, description, location)
          VALUES (new.id, new.title, COALESCE(new.description, ''), COALESCE(new.location, ''));
      END;
      CREATE TRIGGER marketplace_listings_ad AFTER DELETE ON marketplace_listings BEGIN
        INSERT INTO marketplace_listings_fts(marketplace_listings_fts, rowid, title, description, location)
          VALUES ('delete', old.id, old.title, COALESCE(old.description, ''), COALESCE(old.location, ''));
      END;
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS marketplace_listings_ad"
    execute "DROP TRIGGER IF EXISTS marketplace_listings_au"
    execute "DROP TRIGGER IF EXISTS marketplace_listings_ai"
    execute "DROP TABLE IF EXISTS marketplace_listings_fts"
  end
end