# frozen_string_literal: true

class WeeklyStatsJob < ApplicationJob
  queue_as :bulk

  def perform
    stats = {
      posts: Post.count,
      comments: Comment.count,
      users: User.count,
      communities: Community.count,
      reactions: Reaction.count
    }
    Rails.cache.write("brgen:weekly_stats", stats, expires_in: cache_ttl_for(:weekly_stats))
  end

  private

  def cache_ttl_for(key_type)
    if defined?(Shared::CachePolicy)
      Shared::CachePolicy.ttl_for(key_type)
    else
      { weekly_stats: 1.week }.fetch(key_type.to_sym)
    end
  end
end
