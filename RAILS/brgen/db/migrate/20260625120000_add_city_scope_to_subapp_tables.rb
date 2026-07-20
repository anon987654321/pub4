# frozen_string_literal: true

class AddCityScopeToSubappTables < ActiveRecord::Migration[8.1]
  TABLES = %i[
    communities
    marketplace_listings
    marketplace_stores
    dating_profiles
    takeaway_restaurants
    tv_channels
    playlist_playlists
  ].freeze

  def up
    TABLES.each do |table|
      next unless table_exists?(table)
      next if column_exists?(table, :city_id)

      add_reference table, :city, foreign_key: true, null: true
    end

    backfill_city_ids

    return unless table_exists?(:communities) && index_exists?(:communities, :slug)

    remove_index :communities, :slug
    add_index :communities, %i[city_id slug], unique: true
  end

  def down
    if table_exists?(:communities) && index_exists?(:communities, %i[city_id slug])
      remove_index :communities, column: %i[city_id slug]
      add_index :communities, :slug, unique: true
    end

    TABLES.each do |table|
      next unless table_exists?(table)
      next unless column_exists?(table, :city_id)

      remove_reference table, :city, foreign_key: true
    end
  end

  private

  def backfill_city_ids
    return unless table_exists?(:cities)

    default_id = select_value("SELECT id FROM cities ORDER BY id ASC LIMIT 1")
    return unless default_id

    TABLES.each do |table|
      next unless table_exists?(table)
      next unless column_exists?(table, :city_id)

      execute <<~SQL.squish
        UPDATE #{quote_table_name(table)}
        SET city_id = #{quote(default_id)}
        WHERE city_id IS NULL
      SQL
    end

    %i[posts users].each do |table|
      next unless table_exists?(table)
      next unless column_exists?(table, :city_id)

      execute <<~SQL.squish
        UPDATE #{quote_table_name(table)}
        SET city_id = #{quote(default_id)}
        WHERE city_id IS NULL
      SQL
    end
  end
end
