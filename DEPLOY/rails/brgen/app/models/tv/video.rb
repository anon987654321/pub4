# frozen_string_literal: true

class Tv::Video < ApplicationRecord
  # Engine-ized Shared (tranche10)
  include Shared.concern(:ActivityTrackable) rescue nil
  tracks_activity created: "VideoUploaded", updated: "VideoUpdated", source_vertical: "tv", actor: :user
  include Shared::MediaProcessable
  include Shared.concern(:Reactable) rescue nil
  include Shared.concern(:Notifiable) rescue nil

  belongs_to :channel,     class_name: "Tv::Channel",   foreign_key: :tv_channel_id
  belongs_to :user
  has_many :view_events,   class_name: "Tv::ViewEvent", foreign_key: :tv_video_id, dependent: :destroy
  has_many :video_notes,   class_name: "Tv::VideoNote", foreign_key: :video_id, dependent: :destroy
  has_many :comments,      class_name: "Tv::Comment", dependent: :destroy
  has_one_attached :video_file
  has_one_attached :thumbnail
  process_media_variants :thumbnail, variants: {
    poster: { resize_to_limit: [ 1_280, 720 ], format: :webp },
    thumb: { resize_to_limit: [ 480, 270 ], format: :webp }
  }

  STATUSES = %w[processing ready published unlisted].freeze
  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES }, allow_nil: true

  scope :published, -> { where(status: "published").order(published_at: :desc) }
  scope :trending,  -> { published.order(views_count: :desc) }
  scope :recent,    -> { published.order(published_at: :desc) }

  after_update_commit :record_video_published, if: :published_status_change?

  def duration_formatted
    return "—" unless duration_seconds
    h, rem = duration_seconds.divmod(3600)
    m, s   = rem.divmod(60)
    h > 0 ? "%d:%02d:%02d" % [ h, m, s ] : "%d:%02d" % [ m, s ]
  end

  private

  def published_status_change?
    saved_change_to_status? && status == "published"
  end

  def record_video_published
    record_activity!("VideoPublished", actor: user, source_vertical: "tv", visibility: "public")
  end
end
