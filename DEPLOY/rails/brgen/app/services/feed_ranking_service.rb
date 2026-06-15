# frozen_string_literal: true

class FeedRankingService
  WEIGHTS = {
    vote: 3.0,
    comment: 2.0,
    recency: 1.5,
    community: 1.0,
    engagement: 2.0
  }.freeze

  def self.call(user:, scope: Post.all)
    new(user: user, scope: scope).call
  end

  def initialize(user:, scope:)
    @user = user
    @scope = scope
  end

  def call
    return @scope.hot unless @user

    interests = user_interests
    ranked = @scope.left_joins(:votes, :comments, :community)
                   .group("posts.id")
                   .select("posts.*, #{score_sql(interests)} AS feed_score")
                   .order(Arel.sql("feed_score DESC, posts.created_at DESC"))
    ranked
  end

  private

  def user_interests
    raw = @user.try(:feed_interests) || {}
    raw.is_a?(Hash) ? raw : {}
  end

  def score_sql(interests)
    community_boost = interests["communities"].to_a.map(&:to_i)
    tag_boost = interests["tags"].to_a

    parts = [
      "COALESCE(SUM(votes.value), 0) * #{WEIGHTS[:vote]}",
      "COUNT(DISTINCT comments.id) * #{WEIGHTS[:comment]}",
      "(julianday('now') - julianday(posts.created_at)) * -#{WEIGHTS[:recency]}"
    ]

    if community_boost.any?
      parts << "CASE WHEN posts.community_id IN (#{community_boost.join(',')}) THEN #{WEIGHTS[:community]} ELSE 0 END"
    end

    if tag_boost.any?
      like_clauses = tag_boost.map { |t| "posts.content LIKE '%#{ActiveRecord::Base.sanitize_sql_like(t)}%'" }
      parts << "CASE WHEN #{like_clauses.join(' OR ')} THEN #{WEIGHTS[:engagement]} ELSE 0 END"
    end

    "(#{parts.join(' + ')})"
  end
end