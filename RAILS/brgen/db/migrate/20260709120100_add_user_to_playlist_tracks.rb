# frozen_string_literal: true

class AddUserToPlaylistTracks < ActiveRecord::Migration[8.1]
  def change
    add_reference :playlist_tracks, :user, foreign_key: true unless column_exists?(:playlist_tracks, :user_id)
  end
end
