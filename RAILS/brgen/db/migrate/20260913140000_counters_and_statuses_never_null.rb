# frozen_string_literal: true

# Counters that increment! moves, and statuses that scopes filter on, were
# nullable. A nil counter renders as a blank where a number belongs and sorts
# after every zero; a nil status falls out of the `live` scope and the listing
# or order disappears without an error. Each column is backfilled, then given
# the default the model already assumes and NOT NULL.
#
# Where a counter has a source table (tracks on a playlist, likes on a
# playlist) the backfill counts it; views and plays have no source, so nil
# becomes zero.
#
# The indexes serve the queries that already run: the expiry sweeps filter
# messages and typing indicators on expires_at, and the marketplace index
# filters a city's listings by kind and category. The three non-unique
# listing_id indexes on the detail tables duplicate their unique twins.
class CountersAndStatusesNeverNull < ActiveRecord::Migration[8.1]
  NULLABLE_ZERO = {
    marketplace_listings: %i[views_count],
    tv_videos: %i[views_count],
    playlist_playlists: %i[plays_count]
  }.freeze

  def up
    execute(<<~SQL.squish)
      UPDATE playlist_playlists
         SET tracks_count = (SELECT COUNT(*) FROM playlist_playlist_tracks pt WHERE pt.playlist_playlist_id = playlist_playlists.id)
       WHERE tracks_count IS NULL
    SQL
    execute(<<~SQL.squish)
      UPDATE playlist_playlists
         SET likes_count = (SELECT COUNT(*) FROM playlist_likes l WHERE l.playlist_id = playlist_playlists.id)
       WHERE likes_count IS NULL
    SQL
    %i[tracks_count likes_count].each { |column| never_null(:playlist_playlists, column, 0) }

    NULLABLE_ZERO.each do |table, columns|
      columns.each do |column|
        execute("UPDATE #{table} SET #{column} = 0 WHERE #{column} IS NULL")
        never_null(table, column, 0)
      end
    end

    execute("UPDATE marketplace_listings SET status = 'active' WHERE status IS NULL")
    never_null(:marketplace_listings, :status, "active")

    execute("UPDATE takeaway_orders SET status = 'pending' WHERE status IS NULL")
    never_null(:takeaway_orders, :status, "pending")

    execute("UPDATE takeaway_order_items SET quantity = 1 WHERE quantity IS NULL")
    never_null(:takeaway_order_items, :quantity, 1)
    execute("UPDATE takeaway_order_items SET unit_price_cents = 0 WHERE unit_price_cents IS NULL")
    change_column_null :takeaway_order_items, :unit_price_cents, false

    add_index :messages, :expires_at, where: "expires_at IS NOT NULL", if_not_exists: true
    add_index :typing_indicators, :expires_at, if_not_exists: true
    add_index :marketplace_listings, %i[city_id kind category_id], if_not_exists: true

    %w[gig housing job].each do |kind|
      remove_index :"marketplace_#{kind}_details", name: "index_marketplace_#{kind}_details_on_listing_id", if_exists: true
    end
  end

  def down
    %w[gig housing job].each do |kind|
      add_index :"marketplace_#{kind}_details", :listing_id, name: "index_marketplace_#{kind}_details_on_listing_id", if_not_exists: true
    end
    remove_index :marketplace_listings, %i[city_id kind category_id], if_exists: true
    remove_index :typing_indicators, :expires_at, if_exists: true
    remove_index :messages, :expires_at, if_exists: true

    change_column_null :takeaway_order_items, :unit_price_cents, true
    nullable(:takeaway_order_items, :quantity)
    nullable(:takeaway_orders, :status)
    nullable(:marketplace_listings, :status)
    NULLABLE_ZERO.each { |table, columns| columns.each { |column| nullable(table, column) } }
    %i[tracks_count likes_count].each { |column| nullable(:playlist_playlists, column) }
  end

  private

  def never_null(table, column, default)
    change_column_default table, column, default
    change_column_null table, column, false
  end

  def nullable(table, column)
    change_column_null table, column, true
    change_column_default table, column, nil
  end
end
