# frozen_string_literal: true
# AN602: Subdomain feed merging

class UnifiedFeedMerger
  def initialize(user:, city: Current.city)
    @user = user
    @city = city
  end

  def call(limit: 50)
    items = []
    items.concat(posts) if follows_vertical?(:feed)
    items.concat(listings) if follows_vertical?(:marketplace)
    items.concat(dating_activity) if follows_vertical?(:dating)
    items.sort_by { |item| -score(item) }.first(limit)
  end

  private

  attr_reader :user, :city

  def score(item)
    recency = 1.0 / ((Time.current - item[:created_at]) / 1.hour + 2)
    engagement = item[:engagement].to_f
    affinity = item[:affinity].to_f
    recency * engagement * affinity
  end

  def posts
    Post.where(city: city).limit(30).map do |post|
      { type: :post, record: post, created_at: post.created_at, engagement: post.try(:votes_count).to_i + 1, affinity: 1.0 }
    end
  end

  def listings
    Marketplace::Listing.where(city: city).limit(20).map do |listing|
      { type: :listing, record: listing, created_at: listing.created_at, engagement: 1.0, affinity: 0.8 }
    end
  end

  def dating_activity
    Dating::Match.active.where(initiator: user).or(Dating::Match.active.where(receiver: user)).limit(10).map do |match|
      { type: :match, record: match, created_at: match.created_at, engagement: 2.0, affinity: 1.2 }
    end
  end

  def follows_vertical?(vertical)
    return true unless user.respond_to?(:followed_verticals)

    user.followed_verticals.blank? || user.followed_verticals.include?(vertical.to_s)
  end
end