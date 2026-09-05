# frozen_string_literal: true

require "cgi"
require "uri"

class Playlist::Track < ApplicationRecord
  # Engine-ize Shared via pub4-shared
  include Shared::MediaProcessable
  tracks_activity created: "PlaylistTrackCreated", source_vertical: "playlist"
  include Shared::Reactable
  belongs_to :user, optional: true
  has_many :playlist_tracks, class_name: "Playlist::PlaylistTrack",
           foreign_key: :playlist_track_id, dependent: :destroy, inverse_of: :track
  has_many :playlists, through: :playlist_tracks, class_name: "Playlist::Playlist"
  has_many :listens, class_name: "Playlist::Listen",
           foreign_key: :playlist_track_id, dependent: :destroy, inverse_of: :track
  has_many :timestamped_comments, class_name: "Playlist::TimestampedComment",
           foreign_key: :track_id, dependent: :destroy, inverse_of: :track
  has_many :audio_versions, class_name: "Playlist::AudioVersion",
           foreign_key: :track_id, dependent: :destroy, inverse_of: :track
  has_one_attached :audio_file
  has_one_attached :artwork
  process_media_variants :artwork, variants: {
    thumb: { resize_to_limit: [ 320, 320 ], format: :webp },
    cover: { resize_to_limit: [ 1_024, 1_024 ], format: :webp }
  }

  SOURCE_TYPES = %w[upload youtube spotify soundcloud whyp direct dilla].freeze
  PRIVACY_LEVELS = %w[private unlisted public].freeze

  validates :title, presence: true
  validates :artist, presence: true, allow_blank: true
  validates :source_type, inclusion: { in: SOURCE_TYPES }, allow_nil: true
  validates :privacy, inclusion: { in: PRIVACY_LEVELS }, allow_blank: true, if: :privacy_column?

  before_validation :default_audio_hosting_fields

  scope :publicly_visible, -> { privacy_column? ? where(privacy: "public") : all }
  scope :unexpired, -> {
    column_names.include?("expires_at") ? where("expires_at IS NULL OR expires_at > ?", Time.current) : all
  }
  scope :recent, -> { order(created_at: :desc) }

  def visible_to?(viewer)
    level = privacy.to_s
    return true if level.blank? || level == "public"
    viewer.present? && user_id == viewer.id
  end

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
    has_attribute?(:expires_at) && expires_at.present? && expires_at <= Time.current
  end

  def playback_url
    return audio_file if audio_file.attached?
    source_url if source_type == "direct"
  end

  def external_embed_url
    return if audio_file.attached? || source_url.blank?

    case source_type
    when "youtube"
      youtube_embed_url
    when "spotify"
      spotify_embed_url
    when "soundcloud"
      "https://w.soundcloud.com/player/?url=#{CGI.escape(source_url)}"
    when "whyp"
      whyp_embed_url
    end
  end

  def self.privacy_column? = column_names.include?("privacy")

  private

  def privacy_column? = self.class.privacy_column?

  def default_audio_hosting_fields
    self.source_type = "upload" if source_type.blank?
    self.privacy = "private" if privacy_column? && privacy.blank?
  end

  def youtube_embed_url
    uri = URI.parse(source_url)
    id = uri.host.to_s.include?("youtu.be") ? uri.path.delete_prefix("/") : Rack::Utils.parse_query(uri.query)["v"]
    return if id.blank?

    "https://www.youtube.com/embed/#{id}"
  rescue URI::InvalidURIError
    nil
  end

  def spotify_embed_url
    uri = URI.parse(source_url)
    parts = uri.path.split("/").reject(&:blank?)
    return unless parts.length >= 2

    "https://open.spotify.com/embed/#{parts[-2]}/#{parts[-1]}"
  rescue URI::InvalidURIError
    nil
  end

  def whyp_embed_url
    # Support https://whyp.it/tracks/123 or https://www.whyp.it/tracks/123
    # Use /embed for clean customizable player iframe (affiliate partner)
    uri = URI.parse(source_url)
    if uri.path =~ %r{/tracks/(\d+)}
      "https://whyp.it/tracks/#{$1}/embed"
    end
  rescue URI::InvalidURIError
    nil
  end
end
