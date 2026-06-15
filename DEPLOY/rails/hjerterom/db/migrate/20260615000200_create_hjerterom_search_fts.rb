# frozen_string_literal: true

class CreateHjerteromSearchFts < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      CREATE VIRTUAL TABLE resources_fts USING fts5(
        title,
        description,
        resource_type,
        content='resources',
        content_rowid='id'
      );
      INSERT INTO resources_fts(rowid, title, description, resource_type)
        SELECT id, title, COALESCE(description, ''), COALESCE(resource_type, '') FROM resources;

      CREATE VIRTUAL TABLE food_listings_fts USING fts5(
        title,
        description,
        city,
        content='food_listings',
        content_rowid='id'
      );
      INSERT INTO food_listings_fts(rowid, title, description, city)
        SELECT id, title, COALESCE(description, ''), COALESCE(city, '') FROM food_listings;
    SQL
  end

  def down
    execute "DROP TABLE IF EXISTS resources_fts"
    execute "DROP TABLE IF EXISTS food_listings_fts"
  end
end