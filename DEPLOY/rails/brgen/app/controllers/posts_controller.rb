# frozen_string_literal: true

class PostsController < ApplicationController
  before_action :require_real_user, only: [:edit, :update, :destroy]
  before_action :set_post,          only: [:show, :edit, :update, :destroy]
  before_action :set_community,     only: [:new, :create]

  def index
    @posts = Post.hot.includes(:user, :community, :votes)
    @trending_tags = Hashtag.trending.limit(10)
  end

  def show
    @comments    = @post.comments.where(parent_id: nil).best.includes(:user, :votes, replies: [:user, :votes])
    @new_comment = Comment.new
    @trending_tags = Hashtag.trending.limit(10)
    respond_to_cached_show(@post, only: %i[id title content created_at score community_id user_id])
  end

  def new
    @post = Post.new(community: @community)
  end

  def create
    @post           = Post.new(post_params)
    @post.user      = Current.user
    @post.anonymous = true if Current.user.guest?
    @post.community = @community if @community
    if @post.save
      preset = post_params[:preset].presence
      PostproJob.perform_later(@post.to_gid.to_s, preset) if preset && @post.image.attached?
      redirect_to @post, notice: "Posted."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @post.update(post_params)
      redirect_to @post
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @post.destroy
    redirect_to posts_path
  end

  private

  def set_post
    @post = Post.find(params[:id])
  end

  def set_community
    @community = Community.find_by(id: params[:community_id])
  end

  def post_params
    params.expect(post: [:title, :content, :community_id, :anonymous, :image, :preset])
  end
end
