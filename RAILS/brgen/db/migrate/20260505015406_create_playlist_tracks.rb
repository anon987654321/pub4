# frozen_string_literal: true

class CreatePlaylistTracks < ActiveRecord::Migration[8.1]
  def change
    create_table :playlist_tracks do |t|
      t.string :title
      t.string :artist
      t.string :album
      t.integer :duration_seconds
      t.string :genre
      t.string :source_type
      t.string :source_url

      t.timestamps
    end
  end
end
