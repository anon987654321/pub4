# frozen_string_literal: true

class Playlist::PlaylistTrack < ApplicationRecord
  belongs_to :playlist, class_name: "Playlist::Playlist", foreign_key: :playlist_playlist_id,
                        inverse_of: :playlist_tracks
  belongs_to :track,    class_name: "Playlist::Track",    foreign_key: :playlist_track_id, inverse_of: :playlist_tracks
  belongs_to :user

  validates :playlist_playlist_id, uniqueness: { scope: :playlist_track_id }
  default_scope { order(:position) }
end
