# frozen_string_literal: true

class MonthlyAnalyticsRollupJob < ApplicationJob
  queue_as :bulk

  def perform
    rollup = {
      posts: Post.count,
      comments: Comment.count,
      notifications: Notification.count,
      messages: Message.count,
      taken_up: Marketplace::Listing.count
    }
    Rails.cache.write(
      "brgen:analytics:monthly:#{Date.current.beginning_of_month}",
      rollup,
      expires_in: cache_ttl_for(:monthly_rollup)
    )
  end

  private

  def cache_ttl_for(key_type)
    if defined?(Shared::CachePolicy)
      Shared::CachePolicy.ttl_for(key_type)
    else
      { monthly_rollup: 3.months }.fetch(key_type.to_sym)
    end
  end
end
