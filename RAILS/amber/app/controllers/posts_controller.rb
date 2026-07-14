# frozen_string_literal: true

class PostsController < ApplicationController
  before_action :require_real_user, except: %i[index show create]
  before_action :set_post, only: %i[show destroy like]
  before_action :authorize_owner!, only: :destroy

  def index
    @pagy, @posts = pagy(Post.public_feed.includes(:outfit, :item, user: :profile))
  end

  def feed
    @pagy, @posts = pagy(Current.user.feed_posts.includes(:outfit, :item, user: :profile))
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
    anon = Shared::AnonymousPostService.new(request: request, user: Current.user)
    unless anon.allowed?
      redirect_to new_registration_path,
        alert: "Sign up to post more (#{Shared::AnonymousPostService::LIMIT} anonymous posts per browser)."
      return
    end

    @post = Current.user.posts.build(post_params)
    @post.anonymous = true if guest? || ActiveModel::Type::Boolean.new.cast(post_params[:anonymous])

    if @post.save
      anon.record_post!
      @post.record_activity!("AmberPostCreated", source_vertical: "amber") unless guest?
      redirect_to(guest? ? root_path : posts_path, notice: guest? ? "Posted anonymously" : "Posted")
    else
      redirect_to root_path, alert: @post.errors.full_messages.to_sentence
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
  def authorize_owner!
    redirect_to(posts_path, alert: "Unauthorized") unless @post.user == Current.user
  end

  def post_params = params.require(:post).permit(:body, :outfit_id, :item_id, :anonymous)
end
