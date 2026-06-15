# frozen_string_literal: true

class AnalyticsController < ApplicationController
  before_action :require_authentication

  def show
    @blog = Blog.find_by!(slug: params[:blog_id])
    redirect_to(@blog, alert: "Unauthorized") unless @blog.user == Current.user

    @posts = @blog.posts.published.order(views_count: :desc)
    @stats = {
      total_views: @posts.sum(:views_count),
      total_posts: @posts.count,
      avg_views: @posts.average(:views_count)&.round(1),
      top_post: @posts.first
    }
  end
end