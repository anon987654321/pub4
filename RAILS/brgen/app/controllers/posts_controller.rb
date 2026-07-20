# frozen_string_literal: true

class PostsController < ApplicationController
  include Shared::LiveSearchable

  rate_limit to: 30, within: 3.minutes, only: %i[create share],
    with: -> { redirect_to posts_path, alert: "Try again later." }

  before_action :require_real_user, only: [ :edit, :update, :destroy ]
  before_action :require_real_user, only: [ :share ]
  before_action :set_post,          only: [ :show, :edit, :update, :destroy ]
  before_action :authorize_owner,   only: [ :edit, :update, :destroy ]
  before_action :set_community,     only: [ :new, :create ]
  skip_before_action :verify_authenticity_token, only: [ :share ]

  def index
    scope = case params[:sort]
            when "fresh" then Post.fresh
            when "top" then Post.top
            else Post.hot
            end
    scope = scope.with_attached_image.includes(:user, :community, :votes)
    scope = apply_live_search(scope, columns: %w[title content], vertical: "feed") if live_search_query.present?
    @pagy, @posts = pagy(scope)
    finish_live_search(partial: "posts/live_search_results")
  end

  def show
    @comments    = @post.comments.where(parent_id: nil).best.includes(:user, :votes, replies: [ :user, :votes ])
    @new_comment = Comment.new
  end

  def new
    @post = Post.new(community: @community)
  end

  def create
    anon = Shared::AnonymousPost.new(request: request, user: Current.user)
    unless anon.allowed?
      redirect_to new_session_path, alert: "Sign up to post more (#{Shared::AnonymousPost::LIMIT} anonymous posts per browser)."
      return
    end

    @post           = Post.new(post_params)
    @post.user      = Current.user
    @post.anonymous = true if Current.user.guest? || ActiveModel::Type::Boolean.new.cast(post_params[:anonymous])
    if @post.title.blank? && @post.content.present?
      @post.title = @post.content.to_s.lines.first.to_s.strip.presence || @post.content.to_s.strip
      @post.title = @post.title.truncate(300)
    end
    @post.community = @community if @community
    unless PostModeration.new(@post).approve?
      redirect_to new_post_path, alert: "Post blocked by moderation."
      return
    end

    if @post.save
      anon.record_post!

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

  def share
    post = Post.new(
      title: share_title,
      content: share_content,
      community: Community.first,
      user: Current.user
    )

    if post.save
      redirect_to edit_post_path(post), notice: "Shared into a draft"
    else
      redirect_to new_post_path, alert: "Could not create draft"
    end
  end

  private

  def set_post
    @post = Post.includes(:user, :community).find(params[:id])
  end

  def authorize_owner
    return if Current.user == @post.user

    redirect_to @post, alert: "Not allowed"
  end

  def set_community
    @community = Community.find_by(id: params[:community_id])
  end

  def post_params
    params.require(:post).permit(:title, :content, :community_id, :anonymous, :image, :preset)
  end

  def share_title
    params[:title].presence || params[:text].presence || params[:url].presence || "Shared draft"
  end

  def share_content
    [ params[:text].presence, params[:url].presence ].compact.join("\n\n")
  end
end
