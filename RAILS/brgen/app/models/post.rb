# frozen_string_literal: true

class Post < ApplicationRecord
  include CityTenantable
  include Shared::Sluggable # /posts/sol-pa-floyen; from :title, unique per city
  include Shared::GeoLocatable

  include Shared::Votable
  include Shared::Commentable
  include Shared::Taggable
  include Shared::Reactable
  include Shared::MediaProcessable
  tracks_activity created: "PostCreated", source_vertical: "social", actor: :user

  # Jodel-style Live posts: short, hyperlocal, anonymous-by-default.
  LIVE_CONTENT_MAX = 500
  LIVE_RADIUS_KM_DEFAULT = 10.0
  LIVE_RADIUS_KM_MAX = 20.0
  # Coarsen stored coords (~1 km) so Live cannot leak exact GPS.
  LIVE_LOCATION_PRECISION = 2

  has_one_attached :image
  has_one_attached :video
  has_one_attached :audio
  process_media_variants :image, variants: {
    card: { resize_to_limit: [ 800, 800 ], format: :webp },
    hero: { resize_to_limit: [ 1_200, 1_200 ], format: :webp }
  }

  belongs_to :user
  belongs_to :community, optional: true

  has_many :mentions, as: :mentionable, dependent: :destroy
  has_many :reposts, dependent: :destroy
  has_many :reposters, through: :reposts, source: :user

  validates :title,   presence: true, length: { maximum: 300 }
  validates :content, length: { maximum: 40_000 }
  validate :live_content_length, if: :live?

  broadcasts_refreshes

  VOTE_SQL = Arel.sql("SUM(COALESCE(votes.value,0)) DESC, posts.created_at DESC")
  TOP_SQL  = Arel.sql("SUM(COALESCE(votes.value,0)) DESC")
  # "hot" = score decayed by age, so it is a live ranking rather than an all-time
  # leaderboard: score/(age_hours + 2). A high-vote post sinks as it ages and a
  # fresh well-received one can surface. julianday keeps it a single SQLite
  # expression (prod is SQLite); the created_at tiebreaker keeps it deterministic.
  HOT_SQL = Arel.sql(
    "(SUM(COALESCE(votes.value,0)) + 1.0) / " \
    "(((julianday('now') - julianday(posts.created_at)) * 24.0) + 2.0) DESC, " \
    "posts.created_at DESC"
  )
  READING_WORDS_PER_MINUTE = 200

  # Content a moderator has removed never appears in any feed.
  scope :kept,   -> { where(removed_at: nil) }
  scope :hot,    -> { kept.left_joins(:votes).group(:id).order(HOT_SQL) }
  scope :fresh,  -> { kept.order(created_at: :desc) }
  scope :top,    -> { kept.left_joins(:votes).group(:id).order(TOP_SQL) }
  # Geo-stamped Live posts (Jodel layer). Not all posts are Live.
  scope :live,   -> { where.not(latitude: nil).where.not(longitude: nil) }
  scope :search, ->(q) {
    ids = connection.select_values(sanitize_sql_array([ "SELECT rowid FROM posts_fts WHERE posts_fts MATCH ?", q ]))
    ids.any? ? where(id: ids) : none
  }

  def live? = latitude.present? && longitude.present?

  def reposted_by?(user) = Repost.reposted_post_ids_for(user).include?(id)

  def stamp_live_location!(lat:, lng:)
    self.latitude  = lat.to_f.round(LIVE_LOCATION_PRECISION)
    self.longitude = lng.to_f.round(LIVE_LOCATION_PRECISION)
    self.anonymous = true
    self
  end

  # Reads the counter cache column the post is already loaded with. This was
  # comments.count, which queries even when the association is loaded — two
  # queries per feed post, 50 on the home page alone.
  def comment_count = comments_count
  def author_name   = (anonymous? || user&.guest? || live?) ? "anon" : (user&.username.presence || "anon")

  # Same anon check as author_name -- an identicon is only safe to show
  # alongside a real name. Showing it under "anon" too would give every
  # anonymous post from the same user a matching visual signature, letting
  # readers correlate "anon" posts by eye even though the name can't.
  def author_avatar_url
    return nil if anonymous? || user&.guest? || live?
    user&.avatar_url
  end

  def reading_time_minutes
    text = ActionView::Base.full_sanitizer.sanitize(content.to_s)
    words = text.scan(/[[:alnum:]]+(?:['-][[:alnum:]]+)*/).size
    return 0 if words.zero?

    (words / READING_WORDS_PER_MINUTE.to_f).ceil
  end

  private

  def live_content_length
    return if content.blank?
    return if content.to_s.length <= LIVE_CONTENT_MAX

    errors.add(:content, :too_long_for_live, count: LIVE_CONTENT_MAX)
  end
end
