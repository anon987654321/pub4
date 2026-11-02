# frozen_string_literal: true

class AddWhypEmbedUrlToPlaylistTracks < ActiveRecord::Migration[8.2]
  def change
    add_column :playlist_tracks, :embed_url, :string
  end
end
