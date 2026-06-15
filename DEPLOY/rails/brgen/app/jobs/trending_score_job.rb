# frozen_string_literal: true
# AN607: Trending algorithm

class TrendingScoreJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: ->(*_) { "trending" }

  GRAVITY = 1.8

  def perform
    Post.find_each(batch_size: 200) do |post|
      hours = ((Time.current - post.created_at) / 1.hour) + 2
      votes = post.try(:votes_count).to_i
      comments = post.try(:comments_count).to_i
      shares = post.try(:shares_count).to_i
      score = (votes + comments * 2 + shares * 3) / (hours**GRAVITY)
      post.update_column(:trending_score, score) if post.respond_to?(:trending_score)
    end
  end
end