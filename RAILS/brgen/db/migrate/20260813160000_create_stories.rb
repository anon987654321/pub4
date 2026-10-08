# frozen_string_literal: true

# Ephemeral media that expires on its own.
#
# brgen already had ephemerality, but only inside DMs — Conversation's
# disappearing_duration and Message#expires_at with its sweep job. There was no
# 24-hour story, no camera-first capture, and nothing on a profile or the feed
# that goes away by itself.
class CreateStories < ActiveRecord::Migration[8.1]
  def change
    create_table :stories do |t|
      t.references :city, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string   :caption
      # Coarsened like Post's Live layer: a story is often posted from where you
      # are standing, and exact GPS on a public surface is not something to
      # collect by default.
      t.decimal  :latitude,  precision: 10, scale: 6
      t.decimal  :longitude, precision: 10, scale: 6
      t.datetime :expires_at, null: false
      t.integer  :views_count, null: false, default: 0
      t.timestamps
    end

    # The only query any story surface makes: whose stories are still alive.
    add_index :stories, %i[user_id expires_at]
    # The sweep's driving index.
    add_index :stories, :expires_at

    create_table :story_views do |t|
      t.references :story, null: false, foreign_key: true
      t.references :user,  null: false, foreign_key: true
      t.timestamps
    end

    # Seen is a set, not a log: opening a story twice is one view, and the
    # author's viewer list must not repeat a name.
    add_index :story_views, %i[story_id user_id], unique: true
  end
end
