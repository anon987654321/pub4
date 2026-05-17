class CreatePlaylistPlaylists < ActiveRecord::Migration[8.1]
  def change
    create_table :playlist_playlists do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name
      t.text :description
      t.boolean :public_access
      t.integer :plays_count
      t.integer :likes_count
      t.integer :tracks_count

      t.timestamps
    end
  end
end
