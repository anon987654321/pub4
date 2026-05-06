class Playlist::Playlist < ApplicationRecord
  belongs_to :user
  has_many :playlist_tracks, class_name: "Playlist::PlaylistTrack",
           foreign_key: :playlist_playlist_id, dependent: :destroy
  has_many :tracks, through: :playlist_tracks, class_name: "Playlist::Track",
           source: :track

  validates :name, presence: true, length: { maximum: 100 }

  scope :public_playlists, -> { where(public_access: true) }
  scope :popular,           -> { order(plays_count: :desc) }
  scope :recent,            -> { order(created_at: :desc) }

  def add_track!(track, user:)
    pos = playlist_tracks.maximum(:position).to_i + 1
    playlist_tracks.find_or_create_by!(track: track) do |pt|
      pt.position = pos
      pt.user     = user
    end
    increment!(:tracks_count)
  end
end
