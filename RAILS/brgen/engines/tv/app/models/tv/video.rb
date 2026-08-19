# frozen_string_literal: true

class Tv::Video < ApplicationRecord
  # Engine-ized Shared (tranche10)
  tracks_activity created: "VideoUploaded", updated: "VideoUpdated", source_vertical: "tv", actor: :user
  include Shared::Sluggable # /videos/<title-slug>; global uniqueness (no city_id)
  include Shared::MediaProcessable
  include Shared::Reactable
  include Shared::Notifiable
  include Tv::ChannelTenanted

  belongs_to :channel,     class_name: "Tv::Channel",   foreign_key: :tv_channel_id
  belongs_to :user
  has_many :view_events,   class_name: "Tv::ViewEvent", foreign_key: :tv_video_id, dependent: :destroy
  has_many :video_notes,   class_name: "Tv::VideoNote", foreign_key: :video_id, dependent: :destroy
  has_many :comments,      class_name: "Tv::Comment", dependent: :destroy
  # The audio this clip is built on, and — when it answers another clip — the
  # one it answers. Both nullable: most videos carry their own sound and answer
  # nothing.
  belongs_to :sound, class_name: "Tv::Sound", optional: true, counter_cache: :videos_count
  belongs_to :duet_of, class_name: "Tv::Video", optional: true
  has_many :duets, class_name: "Tv::Video", foreign_key: :duet_of_id, dependent: :nullify, inverse_of: :duet_of
# The sound this clip introduced, if it introduced one. :nullify, because the
# sound outlives the clip — the clips built on it are the reason it is still a
# thing, and the schema's foreign key would otherwise refuse the delete.
has_one :originated_sound, class_name: "Tv::Sound", foreign_key: :source_video_id,
        dependent: :nullify, inverse_of: :source_video
  has_one_attached :video_file
  has_one_attached :thumbnail
  process_media_variants :thumbnail, variants: {
    poster: { resize_to_limit: [ 1_280, 720 ], format: :webp },
    thumb: { resize_to_limit: [ 480, 270 ], format: :webp },
  }

  STATUSES = %w[processing ready published unlisted].freeze
  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES }, allow_nil: true

  # in_current_city on the two scopes the public pages read, not on :published —
  # :published is also used by admin and by the channel's own show page, where
  # the channel is already the tenant-scoped record doing the asking.
  scope :published, -> { where(status: "published").order(published_at: :desc) }

  # Trending ranks by watch time, not by page opens. views_count is incremented
  # in videos#show, so a viewer who bounced after four seconds moved a video up
  # exactly as far as one who watched it through — which is the difference
  # between a most-clicked list and a most-watched one.
  #
  # A correlated subquery rather than left_joins + group: the home page passes
  # this scope to pagy, and pagy counts a grouped relation with .count(:all),
  # which returns a hash of per-group counts instead of a number. tv_view_events
  # is indexed on tv_video_id.
  #
  # views_count stays as the tiebreak, so a video nobody has reported watch time
  # for yet still ranks rather than falling to the bottom of the page.
  WATCH_TIME_SQL = <<~SQL.squish
    (SELECT COALESCE(SUM(watch_time_seconds), 0) FROM tv_view_events
      WHERE tv_view_events.tv_video_id = tv_videos.id) DESC,
    tv_videos.views_count DESC
  SQL

  scope :trending,  -> { published.in_current_city.reorder(Arel.sql(WATCH_TIME_SQL)) }
  scope :recent,    -> { published.in_current_city.order(published_at: :desc) }

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

  # Runs in an after_update_commit, where `user` is a lazy belongs_to read on a
  # video that a controller loaded by id. See Shared::StrictSafeAssociations.
  def record_video_published
    record_activity!("VideoPublished", actor: strict_safe(:user), source_vertical: "tv", visibility: "public")
  end
end
