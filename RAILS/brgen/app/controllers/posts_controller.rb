# frozen_string_literal: true

class PostsController < ApplicationController
  include Shared::FindableBySlug
  # Flood protection on content creation (Rails 8 built-in), per-user or per-IP.
  rate_limit to: 12, within: 1.minute, only: :create,
             by: -> { Current.user&.id ? "u#{Current.user.id}" : request.remote_ip }
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

  COMMENT_SORTS = %w[best new top controversial].freeze

  def show
    @comment_sort = COMMENT_SORTS.include?(params[:sort]) ? params[:sort] : "best"
    roots = @post.comments.where(parent_id: nil)
    roots = case @comment_sort
            when "new"           then roots.new_first
            when "top"           then roots.top
            when "controversial" then roots.controversial
            else roots.best
            end
    @comments    = roots.includes(:user, :votes, replies: [ :user, :votes ])
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
    shared_media = Array(params[:media]).select { |f| f.respond_to?(:read) }
    post = Post.new(
      title: share_title.presence || (shared_media.any? ? t("share.photo_title", default: "Shared photo") : nil),
      content: share_content,
      community: Community.first,
      user: Current.user
    )
    # Share Target for images: a photo shared INTO brgen from the camera roll lands
    # attached to a fresh draft (manifest share_target declares files: media).
    post.image.attach(shared_media.first) if shared_media.any? && post.respond_to?(:image)

    if post.save
      redirect_to edit_post_path(post), notice: "Shared into a draft"
    else
      redirect_to new_post_path, alert: "Could not create draft"
    end
  end

  private

  def set_post
    @post = find_by_slug_or_id(Post.includes(:user, :community), params[:id])
    # A moderator-removed post is gone for everyone, including via direct link.
    raise ActiveRecord::RecordNotFound if @post&.removed_at?
  end

  def authorize_owner
    return if Current.user == @post.user

    redirect_to @post, alert: "Not allowed"
  end

  def set_community
    @community = Community.find_by(id: params[:community_id])
  end

  def post_params
    params.require(:post).permit(:title, :content, :community_id, :anonymous, :image, :video, :audio, :preset)
  end

  def share_title
    params[:title].presence || params[:text].presence || params[:url].presence || "Shared draft"
  end

  def share_content
    [ params[:text].presence, params[:url].presence ].compact.join("\n\n")
  end
end
