# frozen_string_literal: true

class MonthlyAnalyticsRollupJob < ApplicationJob
  queue_as :bulk

  def perform
    rollup = {
      posts: Post.count,
      comments: Comment.count,
      notifications: Notification.count,
      messages: Message.count,
      taken_up: Marketplace::Listing.count,
    }
    Rails.cache.write("brgen:analytics:monthly:#{Date.current.beginning_of_month}", rollup, expires_in: 3.months)
  end
end
