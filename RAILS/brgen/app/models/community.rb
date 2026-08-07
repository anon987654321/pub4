# frozen_string_literal: true

class Community < ApplicationRecord
  include CityTenantable

  belongs_to :user, optional: true

  has_many :posts, dependent: :destroy
  has_many :community_memberships, dependent: :destroy
  has_many :members, through: :community_memberships, source: :user

  def member?(user) = user.present? && community_memberships.exists?(user_id: user.id)
  def members_count = community_memberships.count

  validates :name, presence: true, length: { maximum: 100 }
  validates :slug, uniqueness: { scope: :city_id }, allow_nil: true
  validates :description, length: { maximum: 500 }

  POPULAR_SQL = Arel.sql("COUNT(posts.id) DESC")
  scope :popular, -> { left_joins(:posts).group(:id).order(POPULAR_SQL) }

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
    key = ["communities/popular", tenant&.id || "global", limit]
    Rails.cache.fetch(key, expires_in: POPULAR_TTL) { popular.limit(limit).to_a }
  end
end
