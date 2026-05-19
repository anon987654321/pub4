# frozen_string_literal: true

class Playlist::Track < ApplicationRecord
  has_many :playlist_tracks, class_name: "Playlist::PlaylistTrack",
           foreign_key: :playlist_track_id, dependent: :destroy
  has_many :playlists, through: :playlist_tracks, class_name: "Playlist::Playlist"
  has_many :listens, class_name: "Playlist::Listen",
           foreign_key: :playlist_track_id, dependent: :destroy

  SOURCE_TYPES = %w[youtube spotify soundcloud direct].freeze

  validates :title, :artist, presence: true
  validates :source_type, inclusion: { in: SOURCE_TYPES }, allow_nil: true

  def duration_formatted
    return "—" unless duration_seconds
    min, sec = duration_seconds.divmod(60)
    "#{min}:%02d" % sec
  end
end
