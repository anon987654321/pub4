# frozen_string_literal: true

# What this reader searched for lately, for the search palette's blank state.
# One row per (user, query): a repeat search moves the existing row to the top
# rather than accumulating, so the table stays as small as the history it
# represents and the composite unique index is the dedup.
class CreateSearchRecents < ActiveRecord::Migration[8.2]
  def change
    create_table :search_recents do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.string :query, null: false
      t.datetime :last_searched_at, null: false
      t.timestamps
    end
    add_index :search_recents, %i[user_id query], name: "index_search_recents_on_user_id_and_query", unique: true
    add_index :search_recents, %i[user_id last_searched_at], name: "index_search_recents_on_user_id_and_last_searched_at"
  end
end
