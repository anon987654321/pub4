# frozen_string_literal: true

class BookmarksController < ApplicationController
  before_action :require_user_session

  def index
    @pagy, @posts = pagy(
      Current.user.bookmarked_posts.kept
                  .includes(:user, :community, :votes)
                  .order(created_at: :desc)
    )
  end

  def create
    post = Post.find(params[:post_id])
    Current.user.bookmark!(post)
    redirect_back fallback_location: main_app.post_path(post), notice: t("bookmark.saved", default: "Saved.")
  end

  def destroy
    # Scoped to Current.user's own bookmarks.
    Current.user.bookmarks.find_by(post_id: params[:post_id])&.destroy
    redirect_back fallback_location: main_app.post_path(params[:post_id]), notice: t("bookmark.removed", default: "Removed.")
  end
end
