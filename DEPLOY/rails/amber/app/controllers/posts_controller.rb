# frozen_string_literal: true

class PostsController < ApplicationController
  before_action :set_post, only: %i[show destroy like]

  def index
    @pagy, @posts = pagy(Post.recent.includes(:user, :outfit, :item))
  end

  def feed
    @pagy, @posts = pagy(Current.user.feed_posts.includes(:user, :outfit, :item))
  end

  def show
    @comments = @post.root_comments
    @comment = Comment.new
    @post.record_activity!("AmberPostViewed", source_vertical: "amber")
  end

  def new
    @post = Post.new
  end

  def create
    @post = Current.user.posts.build(post_params)
    if @post.save
      @post.record_activity!("AmberPostCreated", source_vertical: "amber")
      redirect_to(posts_path, notice: "Posted")
    else
      render(:new, status: :unprocessable_entity)
    end
  end

  def destroy
    @post.record_activity!("AmberPostRemoved", source_vertical: "amber")
    @post.destroy!
    redirect_to posts_path
  end

  def like
    @post.like!
    @post.record_activity!("AmberPostLiked", source_vertical: "amber")
    redirect_back fallback_location: posts_path
  end

  private

  def set_post = @post = Post.find(params[:id])
  def post_params = params.require(:post).permit(:body, :outfit_id, :item_id)
end
