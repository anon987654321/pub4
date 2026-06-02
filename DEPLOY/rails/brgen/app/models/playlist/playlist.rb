# frozen_string_literal: true

class Playlist::Playlist < ApplicationRecord
  belongs_to :user
  has_many :playlist_tracks, class_name: "Playlist::PlaylistTrack",
           foreign_key: :playlist_playlist_id, dependent: :destroy
  has_many :tracks, through: :playlist_tracks, class_name: "Playlist::Track",
           source: :track
  has_many :collaborations, class_name: "Playlist::Collaboration", dependent: :destroy
  has_many :collaborators, through: :collaborations, source: :user
  has_many :dilla_sketches, class_name: "Playlist::DillaSketch", dependent: :destroy

  validates :name, presence: true, length: { maximum: 100 }

  scope :public_playlists, -> { where(public_access: true) }
  scope :popular,           -> { order(plays_count: :desc) }
  scope :recent,            -> { order(created_at: :desc) }

  def add_track!(track, user:)
    playlist_track = playlist_tracks.find_or_initialize_by(track: track)
    return playlist_track if playlist_track.persisted?

    position = playlist_tracks.maximum(:position).to_i + 1
    playlist_track.position = position
    playlist_track.user = user
    playlist_track.save!
    increment!(:tracks_count)
    playlist_track
  end
end
