# frozen_string_literal: true

class FeedsController < ApplicationController
  allow_unauthenticated_access only: %i[show blog]

  def show
    @posts = published_posts.limit(50)
    expires_in 15.minutes, public: true
    respond_to do |format|
      format.rss { render layout: false }
      format.atom { render layout: false }
    end
  end

  def blog
    @blog = Blog.find(params[:blog_id])
    @posts = @blog.posts.published.includes(:user, :blog).limit(50)
    expires_in 15.minutes, public: true
    respond_to do |format|
      format.rss { render :show, layout: false }
      format.atom { render :show, layout: false }
    end
  end

  private

  def published_posts
    Post.published.includes(:user, :blog).order(published_at: :desc)
  end
end