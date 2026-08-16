# frozen_string_literal: true

class BookmarksController < ApplicationController
  include Shared::FindableBySlug
  before_action :require_user_session

  def index
    @pagy, @posts = pagy(
      Current.user.bookmarked_posts.kept
                  .includes(:user, :community, :votes)
                  .order(created_at: :desc)
    )
  end

  def create
    post = find_by_slug_or_id(Post.includes(:community), params[:post_id])
    raise ActiveRecord::RecordNotFound unless post.readable_by?(Current.user)
    Current.user.bookmark!(post)
    redirect_back fallback_location: main_app.post_path(post), notice: t("bookmark.saved")
  end

  def destroy
    post = find_by_slug_or_id(Post, params[:post_id])
    # Scoped to Current.user's own bookmarks.
    Current.user.bookmarks.find_by(post_id: post.id)&.destroy
    redirect_back fallback_location: main_app.post_path(post), notice: t("bookmark.removed")
  end
end
