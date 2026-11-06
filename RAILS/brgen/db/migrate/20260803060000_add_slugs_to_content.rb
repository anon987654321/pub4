# frozen_string_literal: true

# Beautiful URL slugs for the five user-facing content types that had a numeric
# `show` route. tv_channels / tv_shows / marketplace_stores already carried a slug
# column, so they are untouched here. Each column is added nullable, backfilled from
# its title/name with the same parameterize + numeric-suffix logic Shared::Sluggable
# uses at runtime (city-scoped where the table has city_id, global otherwise), then a
# unique index is added AFTER backfill so no row trips it mid-fill. Old /posts/123
# links keep resolving — controllers fall back to id when a slug lookup misses.
class AddSlugsToContent < ActiveRecord::Migration[8.1]
  # table => source column for the slug base
  SOURCES = {
    posts: :title,
    tv_videos: :title,
    takeaway_restaurants: :name,
    playlist_playlists: :name,
    marketplace_listings: :title
  }.freeze

  def up
    SOURCES.each_key do |table|
      add_column table, :slug, :string unless column_exists?(table, :slug)
    end

    SOURCES.each { |table, source| backfill(table, source) }

    # Unique indexes matching Shared::Sluggable's scope: [city_id, slug] where the
    # table is tenant-scoped, plain slug otherwise.
    add_index :posts, %i[city_id slug], unique: true, name: "index_posts_on_city_and_slug"
    add_index :takeaway_restaurants, %i[city_id slug], unique: true, name: "index_takeaway_restaurants_on_city_and_slug"
    add_index :playlist_playlists, %i[city_id slug], unique: true, name: "index_playlist_playlists_on_city_and_slug"
    add_index :marketplace_listings, %i[city_id slug], unique: true, name: "index_marketplace_listings_on_city_and_slug"
    add_index :tv_videos, :slug, unique: true, name: "index_tv_videos_on_slug"
  end

  def down
    remove_index :posts, name: "index_posts_on_city_and_slug"
    remove_index :takeaway_restaurants, name: "index_takeaway_restaurants_on_city_and_slug"
    remove_index :playlist_playlists, name: "index_playlist_playlists_on_city_and_slug"
    remove_index :marketplace_listings, name: "index_marketplace_listings_on_city_and_slug"
    remove_index :tv_videos, name: "index_tv_videos_on_slug"
    SOURCES.each_key { |table| remove_column table, :slug }
  end

  private

  # Throwaway AR class so the backfill runs without loading the real models (whose
  # Sluggable include would itself expect the column to exist).
  def backfill(table, source)
    klass = Class.new(ActiveRecord::Base) { self.table_name = table }
    klass.reset_column_information
    has_city = klass.column_names.include?("city_id")
    used = Hash.new { |h, k| h[k] = {} } # scope key => { slug => true }

    klass.where(slug: nil).find_each do |record|
      base = record[source].to_s.parameterize
      base = "item" if base.blank?
      scope_key = has_city ? record.city_id : :global
      taken = used[scope_key]

      candidate = base
      n = 2
      while taken[candidate]
        candidate = "#{base}-#{n}"
        n += 1
      end
      taken[candidate] = true
      record.update_column(:slug, candidate)
    end
  end
end
