# frozen_string_literal: true

# Booleans that could be nil, and so were three-state columns pretending to be
# two. Every reader of these eight already treated nil as false — `where(flag:
# true)` skips it, `flag?` returns false for it — so this changes no behaviour.
# What it removes is the third state: a row where "is this on?" has no answer,
# and a `where.not(flag: true)` that quietly misses it.
#
# amber's items.spark_joy is deliberately NOT here, and was reverted after
# being tried. It is a real three-state column: WardrobeAi#heuristic_joy
# branches `== true` / `== false` / else, and TasteRanker scores nil at 0.5
# against false at 0.0 — nil means "not asked yet", which is a different fact
# from "no". Collapsing it stopped a high-wear item reading as a keeper.
#
# tv_view_events.completed is out for the same reason, found the same way — by
# the suite. Tv::ViewEvent#record_progress! writes
# `limit ? seconds >= limit * COMPLETION_THRESHOLD : completed`, so a video
# with no duration leaves it nil on purpose: "we cannot know whether this was
# finished" is a different claim from "it was not finished".
class BooleanDefaultsForNilableFlags < ActiveRecord::Migration[8.1]
  COLUMNS = [
    %w[dating_profiles visible],
    %w[playlist_playlists public_access],
    %w[posts anonymous],
    %w[takeaway_menu_items vegan],
    %w[takeaway_menu_items vegetarian],
    %w[takeaway_restaurants active],
    %w[tv_subscriptions notify_on_upload]
  ].freeze

  def up
    COLUMNS.each do |table, column|
      next unless column_exists?(table, column)

      execute("UPDATE #{quote_table_name(table)} SET #{quote_column_name(column)} = 0 " \
              "WHERE #{quote_column_name(column)} IS NULL")
      change_column_default(table, column, from: nil, to: false)
      change_column_null(table, column, false)
    end
  end

  def down
    COLUMNS.each do |table, column|
      next unless column_exists?(table, column)

      change_column_null(table, column, true)
      change_column_default(table, column, from: false, to: nil)
    end
  end
end
