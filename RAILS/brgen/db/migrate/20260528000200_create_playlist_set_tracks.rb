# frozen_string_literal: true

class CreatePlaylistSetTracks < ActiveRecord::Migration[8.1]
  def change
    create_table :playlist_set_tracks do |t|
      t.references :playlist_set, null: false, foreign_key: true
      t.references :playlist_track, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :playlist_set_tracks, %i[playlist_set_id playlist_track_id], unique: true
  end
end
