# frozen_string_literal: true

class AddCollaborativeToPlaylistPlaylists < ActiveRecord::Migration[8.1]
  def change
    add_column :playlist_playlists, :collaborative, :boolean, null: false, default: false
  end
end
