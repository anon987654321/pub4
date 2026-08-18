# frozen_string_literal: true

class Community < ApplicationRecord
  include CityTenantable
  include Shared::MediaProcessable

  PRIVACIES = %w[public restricted private].freeze

  belongs_to :user, optional: true

  has_many :posts, dependent: :destroy
  has_many :community_memberships, dependent: :destroy
  has_many :members, through: :community_memberships, source: :user
  has_many :moderator_memberships, -> { where(role: %w[moderator owner]) },
           class_name: "CommunityMembership", inverse_of: :community, dependent: nil
  has_many :moderators, through: :moderator_memberships, source: :user
  has_many :community_bans, dependent: :destroy
  has_many :banned_users, through: :community_bans, source: :user

  has_one_attached :icon
  has_one_attached :banner
  process_media_variants :icon, variants: {
    thumb: { resize_to_limit: [ 128, 128 ], format: :webp },
  }
  process_media_variants :banner, variants: {
    hero: { resize_to_limit: [ 1_600, 400 ], format: :webp },
  }

  validates :name, presence: true, length: { maximum: 100 }
  validates :slug, uniqueness: { scope: :city_id }, allow_nil: true
  validates :description, length: { maximum: 500 }
  validates :rules, length: { maximum: 10_000 }
  validates :privacy, inclusion: { in: PRIVACIES }

  scope :visible_to, lambda { |user|
    # A private community is not listed to non-members. Its posts are separately
    # gated in the controller — this only keeps it out of directories.
    next where.not(privacy: "private") if user.blank?

    where.not(privacy: "private")
      .or(where(id: CommunityMembership.where(user_id: user.id).select(:community_id)))
  }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :active, -> { where(archived_at: nil) }

  POPULAR_SQL = Arel.sql("COUNT(posts.id) DESC")
  scope :popular, -> { active.left_joins(:posts).group(:id).order(POPULAR_SQL) }

  # The home page renders ten sidebar links from this, and `popular` joins and
  # groups every post in the city to produce them. Measured 2026-08-07 on
  # production: the front page answered in 4.1s TTFB while /posts, rendering the
  # same feed without this call, answered in 0.83s at the same payload size.
  #
  # Which communities are busiest changes over hours, not seconds, so the ranking
  # is cached per city. A stale entry costs a slightly out-of-date sidebar; the
  # uncached version costs a full scan on every visit to the front door.
  POPULAR_TTL = 10.minutes

  def self.popular_cached(limit: 10, tenant: ActsAsTenant.current_tenant)
    key = [ "communities/popular", tenant&.id || "global", limit ]
    Rails.cache.fetch(key, expires_in: POPULAR_TTL) { popular.limit(limit).to_a }
  end

  def member?(user) = membership_for(user).present?

  def moderator?(user)
    membership_for(user)&.role.in?(%w[moderator owner])
  end

  def owner?(user)
    # The creator is the owner even before any membership row exists, so a
    # community is never left with nobody able to appoint a moderator.
    return true if user.present? && user_id == user.id

    membership_for(user)&.role == "owner"
  end

  def membership_for(user)
    return nil if user.blank?

    community_memberships.find_by(user_id: user.id)
  end

  # Reading and posting are separate questions. Restricted is the interesting
  # one: the whole city can read it, only members can post.
  def readable_by?(user)
    privacy != "private" || owner?(user) || member?(user)
  end

  def postable_by?(user)
    return false if user.blank? || archived?
    # Checked before privacy, because a public community is exactly where a ban
    # has to bite: anyone may post there, which is what made the mod queue
    # unable to stop a repeat offender at all.
    return false if banned?(user)

    case privacy
    when "public" then true
    else member?(user)
    end
  end

  def banned?(user)
    return false if user.blank?

    community_bans.active.exists?(user_id: user.id)
  end

  # By id, and memoised: the mod queue asks this once per row, and reading
  # `report.reportable.user` to ask it is a lazy association read on a
  # strict-loading record — which raised the whole page rather than showing a
  # ban button.
  def banned_user_ids
    @banned_user_ids ||= community_bans.active.pluck(:user_id).to_set
  end

  def ban_for(user) = user.present? ? community_bans.active.find_by(user_id: user.id) : nil

  def archived? = archived_at.present?

  # One per line, because a fixed flair vocabulary across every community in
  # every city is not a thing that exists.
  def flair_options
    flairs.to_s.lines.map(&:strip).reject(&:empty?)
  end

  def rule_list
    rules.to_s.lines.map(&:strip).reject(&:empty?)
  end

  # Reports against anything posted here. ModerationReport is polymorphic and
  # global, and its own table has no community_id — so the queue is derived from
  # the posts and comments that belong to this community rather than duplicated
  # onto the report.
  def moderation_queue
    post_ids = posts.select(:id)
    ModerationReport.where(reportable_type: "Post", reportable_id: post_ids)
                    .or(ModerationReport.where(
                          reportable_type: "Comment",
                          reportable_id: Comment.where(commentable_type: "Post", commentable_id: post_ids).select(:id)
                        ))
                    .recent
  end
end
