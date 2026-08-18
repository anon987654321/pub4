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
    hero: { resize_to_limit: [ 1_200, 1_200 ], format: :webp },
  }

  belongs_to :user
  belongs_to :community, optional: true

  has_many :mentions, as: :mentionable, dependent: :destroy
  has_many :reposts, dependent: :destroy
  has_many :reposters, through: :reposts, source: :user
  # The same content in a second community, with its own comment thread. A
  # repost is the other act: it boosts into followers' timelines and belongs to
  # no community. :nullify, because a crosspost outlives its source — the second
  # community's thread is that community's, not a view of somebody else's post.
  belongs_to :crossposted_from, class_name: "Post", optional: true, counter_cache: :crossposts_count
  has_many :crossposts, class_name: "Post", foreign_key: :crossposted_from_id, dependent: :nullify, inverse_of: :crossposted_from

  validates :title,   presence: true, length: { maximum: 300 }
  validates :content, length: { maximum: 40_000 }
  validate :live_content_length, if: :live?
  validate :crosspost_lands_somewhere_new, if: :crosspost?

  broadcasts_refreshes

  # Federate public posts only. A post in a community is scoped to that
  # community's rules and privacy setting, and an anonymous one has no author to
  # attribute — neither belongs in an outbox that says who wrote what.
  after_commit :federate_creation, on: :create
  after_commit :federate_deletion, on: :destroy

  VOTE_SQL = Arel.sql("posts.score DESC, posts.created_at DESC")
  TOP_SQL  = Arel.sql("posts.score DESC")
  # "hot" = score decayed by age, so it is a live ranking rather than an all-time
  # leaderboard: score/(age_hours + 2). A high-vote post sinks as it ages and a
  # fresh well-received one can surface. julianday keeps it a single SQLite
  # expression (prod is SQLite); the created_at tiebreaker keeps it deterministic.
  HOT_SQL = Arel.sql(
    "(posts.score + 1.0) / " \
    "(((julianday('now') - julianday(posts.created_at)) * 24.0) + 2.0) DESC, " \
    "posts.created_at DESC"
  )
  READING_WORDS_PER_MINUTE = 200

  # Content a moderator has removed never appears in any feed.
  scope :kept,   -> { where(removed_at: nil) }
  # Community#show already refuses a private community. Feeds, search, and
  # /posts/:slug did not, so a hidden link was the whole permission model.
  scope :visible_to, lambda { |user|
    rel = left_outer_joins(:community)
    if user.present?
      member_ids = user.community_memberships.select(:community_id)
      rel.where(
        "communities.id IS NULL OR communities.privacy != ? OR communities.id IN (?) OR communities.user_id = ?",
        "private", member_ids, user.id
      )
    else
      rel.where("communities.id IS NULL OR communities.privacy != ?", "private")
    end
  }
  scope :hot,    -> { kept.order(HOT_SQL) }
  scope :fresh,  -> { kept.order(created_at: :desc) }
  scope :top,    -> { kept.order(TOP_SQL) }
  # Geo-stamped Live posts (Jodel layer). Not all posts are Live.
  scope :live,   -> { where.not(latitude: nil).where.not(longitude: nil) }
  scope :search, ->(q) {
    ids = connection.select_values(sanitize_sql_array([ "SELECT rowid FROM posts_fts WHERE posts_fts MATCH ?", q ]))
    ids.any? ? where(id: ids) : none
  }

  def live? = latitude.present? && longitude.present?
  def crosspost? = crossposted_from_id.present?

  # Built rather than created here: the caller saves it, and a crosspost of a
  # crosspost points at the original — a chain would make "seen in 4 communities"
  # unanswerable without walking it.
  def build_crosspost(community:, user:)
    # strict_safe, because the post was found by slug with nothing preloaded and
    # this read happens on the way to a write.
    root = strict_safe(:crossposted_from) || self
    root.crossposts.build(
      user: user, community: community, title: root.title, content: root.content,
      anonymous: root.anonymous?
    )
  end

  def readable_by?(user)
    community.blank? || community.readable_by?(user)
  end

  def reposted_by?(user) = Repost.reposted_post_ids_for(user).include?(id)
  def quote_comment_by(user) = Repost.quote_comments_for(user)[id]

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

  def federatable_post?
    community_id.nil? && !anonymous? && !live? && strict_safe(:user)&.federated?
  end

  def federate_creation
    return unless federatable_post?

    Fediverse::DistributeJob.perform_later(
      user_id: user_id, payload: Fediverse::Serializer.create(self).to_json
    )
  end

  # Sent on destroy rather than left to expire: a follower's instance keeps its
  # copy indefinitely, so a post deleted here stays visible there forever unless
  # we say so. The payload is built here, while the record is still in memory —
  # a job given an id would have nothing left to load.
  def federate_deletion
    return unless federatable_post?

    Fediverse::DistributeJob.perform_later(
      user_id: user_id, payload: Fediverse::Serializer.delete(self).to_json
    )
  end

  def live_content_length
    return if content.blank?
    return if content.to_s.length <= LIVE_CONTENT_MAX

    errors.add(:content, :too_long_for_live, count: LIVE_CONTENT_MAX)
  end

  # A crosspost into the community the post is already in is the post again, and
  # a second one into a community it already reached is a duplicate thread.
  def crosspost_lands_somewhere_new
    source = crossposted_from
    return errors.add(:community, :blank) if community_id.blank?
    return errors.add(:community, :same_as_source) if source && source.community_id == community_id

    return unless source&.crossposts&.where(community_id: community_id)&.where&.not(id: id)&.exists?

    errors.add(:community, :already_crossposted)
  end
end
