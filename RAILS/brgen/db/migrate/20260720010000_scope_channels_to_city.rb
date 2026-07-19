# frozen_string_literal: true

# Geo-scoped channels: each city gets its own room per slug, so #takeaway on
# brgen.no (Bergen) and on oshlo.no (Oslo) are distinct rooms with their own
# locals + bots. The slug uniqueness moves from global to per-city; DMs/groups
# (slug NULL, city_id NULL) stay unaffected — SQLite treats NULLs as distinct.
class ScopeChannelsToCity < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :city_id, :integer
    add_index :conversations, :city_id

    remove_index :conversations, name: "index_conversations_on_slug"
    add_index :conversations, %i[slug city_id], unique: true, name: "index_conversations_on_slug_and_city"
  end
end
