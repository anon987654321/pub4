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
    anon = Shared::AnonymousPost.new(request: request, user: Current.user)
    unless anon.allowed?
      redirect_to new_registration_path,
        alert: t("flash.anonymous_post_limit", limit: Shared::AnonymousPost::LIMIT)
      return
    end

    @post = Current.user.posts.build(post_params)
    @post.anonymous = true if guest? || ActiveModel::Type::Boolean.new.cast(post_params[:anonymous])

    if @post.save
      anon.record_post!
      @post.record_activity!("AmberPostCreated", source_vertical: "amber") unless guest?
      redirect_to(guest? ? root_path : posts_path,
                  notice: t(guest? ? "flash.posted_anonymously" : "flash.posted"))
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

  # posts#show reads user, outfit and item directly, and the Article schema
  # reads the author again. Bare `find` left all three to lazy loading, which
  # strict_loading refuses outright — the page only worked because production
  # does not enable it.
  def set_post = @post = Post.includes(:user, :outfit, :item).find(params[:id])
  def authorize_owner!
    redirect_to(posts_path, alert: t("shared.flash.not_authorized")) unless @post.user == Current.user
  end

  def post_params
    permitted = params.require(:post).permit(:body, :outfit_id, :item_id, :anonymous)
    if permitted[:outfit_id].present? && Current.user.outfits.where(id: permitted[:outfit_id]).none?
      permitted[:outfit_id] = nil
    end
    if permitted[:item_id].present? && Current.user.items.where(id: permitted[:item_id]).none?
      permitted[:item_id] = nil
    end
    permitted
  end
end
