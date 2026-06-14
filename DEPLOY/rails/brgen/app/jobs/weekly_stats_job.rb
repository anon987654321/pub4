# frozen_string_literal: true

class WeeklyStatsJob < ApplicationJob
  queue_as :bulk

  def perform
    stats = {
      posts: Post.count,
      comments: Comment.count,
      users: User.count,
      communities: Community.count,
      reactions: Reaction.count,
    }
    Rails.cache.write("brgen:weekly_stats", stats, expires_in: 1.week)
  end
end
