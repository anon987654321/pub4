class CreatePlaylistListens < ActiveRecord::Migration[8.1]
  def change
    create_table :playlist_listens do |t|
      t.references :user, null: false, foreign_key: true
      t.references :playlist_track, null: false, foreign_key: true

      t.timestamps
    end
  end
end
