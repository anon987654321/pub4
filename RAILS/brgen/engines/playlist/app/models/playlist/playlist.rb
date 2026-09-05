# frozen_string_literal: true

class Playlist::Playlist < ApplicationRecord
  include CityTenantable
  include Shared::Sluggable # /playlists/<name-slug>; from :name, unique per city
  sluggable_from :name

  # Engine-ize Shared via pub4-shared
  tracks_activity created: "PlaylistCreated", source_vertical: "playlist", actor: :user
  include Shared::Reactable
  include Shared::Notifiable
  include Shared::GeoLocatable
  belongs_to :user
  has_many :playlist_tracks, class_name: "Playlist::PlaylistTrack",
           foreign_key: :playlist_playlist_id, dependent: :destroy, inverse_of: :playlist
  has_many :tracks, through: :playlist_tracks, class_name: "Playlist::Track",
           source: :track
  has_many :collaborations, class_name: "Playlist::Collaboration", dependent: :destroy
  has_many :collaborators, through: :collaborations, source: :user
  has_many :dilla_sketches, class_name: "Playlist::DillaSketch", dependent: :destroy

  validates :name, presence: true, length: { maximum: 100 }

  scope :public_playlists, -> { where(public_access: true) }
  scope :popular,           -> { order(plays_count: :desc) }
  scope :recent,            -> { order(created_at: :desc) }
  scope :city_trending, ->(city = Current.city_record) {
    relation = public_playlists
    relation = relation.where(city: city) if city.present? && column_names.include?("city_id")
    relation.order(plays_count: :desc, tracks_count: :desc, updated_at: :desc)
  }

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

  def duration_seconds
    tracks.unexpired.sum(:duration_seconds)
  end
end
