# frozen_string_literal: true

class AddPlaylistImportEmbedAndExpiryFields < ActiveRecord::Migration[8.1]
  def change
    add_column :playlist_tracks, :privacy, :string, default: "private", null: false
    add_column :playlist_tracks, :expires_at, :datetime
    add_column :playlist_tracks, :audio_replaced_at, :datetime
    add_index :playlist_tracks, %i[privacy expires_at]
  end
end
