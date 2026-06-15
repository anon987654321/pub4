# frozen_string_literal: true

class Playlist::Track < ApplicationRecord
  has_many :playlist_tracks, class_name: "Playlist::PlaylistTrack",
           foreign_key: :playlist_track_id, dependent: :destroy
  has_many :playlists, through: :playlist_tracks, class_name: "Playlist::Playlist"
  has_many :listens, class_name: "Playlist::Listen",
           foreign_key: :playlist_track_id, dependent: :destroy
  has_many :timestamped_comments, class_name: "Playlist::TimestampedComment",
           foreign_key: :track_id, dependent: :destroy
  has_many :audio_versions, class_name: "Playlist::AudioVersion",
           foreign_key: :track_id, dependent: :destroy
  has_one_attached :audio_file
  has_one_attached :artwork

  SOURCE_TYPES = %w[upload youtube spotify soundcloud direct].freeze
  PRIVACY_LEVELS = %w[private unlisted public].freeze

  validates :title, presence: true
  validates :artist, presence: true, allow_blank: true
  validates :source_type, inclusion: { in: SOURCE_TYPES }, allow_nil: true
  validates :privacy, inclusion: { in: PRIVACY_LEVELS }, allow_blank: true

  before_validation :default_audio_hosting_fields

  scope :publicly_visible, -> { where(privacy: "public") }
  scope :unexpired, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }
  scope :recent, -> { order(created_at: :desc) }
  scope :search, ->(q) {
    term = q.to_s.strip
    return none if term.empty?

    ids = connection.select_values(
      sanitize_sql_array(["SELECT rowid FROM playlist_tracks_fts WHERE playlist_tracks_fts MATCH ?", term])
    )
    ids.any? ? where(id: ids) : none
  }

  def duration_formatted
    return "—" unless duration_seconds
    min, sec = duration_seconds.divmod(60)
    "#{min}:%02d" % sec
  end

  def replace_audio!(file, actor: nil)
    if audio_file.attached?
      audio_versions.create!(user: actor, original_filename: audio_file.filename.to_s, byte_size: audio_file.byte_size)
    end

    audio_file.attach(file)
    touch(:audio_replaced_at)
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  private

  def default_audio_hosting_fields
    self.source_type = "upload" if source_type.blank?
    self.privacy = "private" if privacy.blank?
  end
end
