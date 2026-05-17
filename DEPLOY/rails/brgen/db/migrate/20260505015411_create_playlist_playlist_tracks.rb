class CreatePlaylistPlaylistTracks < ActiveRecord::Migration[8.1]
  def change
    create_table :playlist_playlist_tracks do |t|
      t.references :playlist_playlist, null: false, foreign_key: true
      t.references :playlist_track, null: false, foreign_key: true
      t.integer :position
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
