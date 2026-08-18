# frozen_string_literal: true

class PostsController < ApplicationController
  include Shared::FindableBySlug
  # Flood protection on content creation (Rails 8 built-in), per-user or per-IP.
  # `name:` is what keeps this and the sustained limit below separate — unnamed,
  # both build the cache key ["rate-limit", controller_path, nil, by] and share a
  # counter for every signed-out request. See RAILS/test/rate_limit_naming_test.rb.
  rate_limit to: 12, within: 1.minute, only: :create, name: "burst",
             by: -> { Current.user&.id ? "u#{Current.user.id}" : request.remote_ip }
  before_action :require_verified_email, only: :create
  include Shared::LiveSearchable

  rate_limit to: 30, within: 3.minutes, only: %i[create share], name: "sustained",
    with: -> { redirect_to posts_path, alert: t("shared.flash.rate_limited") }

# ONE declaration. Rails deduplicates callbacks by filter name, so declaring
# :require_real_user twice did not add a second gate -- the later `only:`
# REPLACED the earlier one, and edit/update/destroy silently lost it. Read off
# the callback chain: PostsController had exactly one require_real_user.
# authorize_owner still covered those three here, which is why nothing broke
# visibly; amber's ItemsController had the identical pattern with nothing
# behind it and served an anonymous GET /items/new 200.
before_action :require_real_user, only: %i[edit update destroy share]
  before_action :set_post,          only: [ :show, :edit, :update, :destroy ]
  before_action :authorize_owner,   only: [ :edit, :update, :destroy ]
  before_action :set_community,     only: [ :new, :create ]
  before_action :enforce_community_posting_rules, only: :create
  skip_before_action :verify_authenticity_token, only: [ :share ]

  def index
    scope = case params[:sort]
            when "fresh" then Post.fresh
            when "top" then Post.top
            else Post.hot
            end
    scope = Post.visible_to(Current.user).merge(scope)
    scope = scope.with_attached_image.includes(:user, :community, :votes)
    scope = apply_live_search(scope, columns: %w[title content], vertical: "feed") if live_search_query.present?
    @pagy, @posts = pagy(scope)
    finish_live_search(partial: "posts/live_search_results")
  end

  COMMENT_SORTS = %w[best new top controversial].freeze

  def show
    return render_members_only unless @post.readable_by?(Current.user)

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
    @quotes      = @post.reposts.quoted.includes(:user).order(created_at: :desc)
    @quote_comment = @post.quote_comment_by(Current.user)
    @crossposts = (@post.crossposted_from || @post).crossposts.includes(:community).where.not(id: @post.id)
    # Where this post can still go. Communities the reader may post in, minus
    # the one it is already in and the ones it already reached — an option that
    # answers "already crossposted" is a control that does nothing.
    @crosspost_targets = crosspost_targets_for(@post)
  end

  def new
    @post = Post.new(community: @community)
  end

  def create
    anon = Shared::AnonymousPost.new(request: request, user: Current.user)
    unless anon.allowed?
      redirect_to new_session_path, alert: t("flash.anonymous_post_limit", limit: Shared::AnonymousPost::LIMIT)
      return
    end

    @post           = Post.new(post_params.except(:nearby))
    @post.user      = Current.user
    @post.anonymous = true if Current.user.guest? || ActiveModel::Type::Boolean.new.cast(post_params[:anonymous])
    stamp_nearby!
    if @post.title.blank? && @post.content.present?
      @post.title = @post.content.to_s.lines.first.to_s.strip.presence || @post.content.to_s.strip
      @post.title = @post.title.truncate(300)
    end
    @post.community = @community if @community
    verdict = PostModeration.new(@post).decide
    unless verdict.approved
      # Named refusals. The one generic message was fine while the only rejection
      # path was an LLM saying no; the link rule needs to tell the author what to
      # change, or it reads as the site being broken.
      key = verdict.reason == :unverified_author_spam_signals ? "flash.link_requires_verified_account"
                                                           : "flash.post_blocked_by_moderation"
      redirect_to new_post_path, alert: t(key)
      return
    end

    if @post.save
      anon.record_post!

      preset = post_params[:preset].presence
      PostproJob.perform_later(@post.to_gid.to_s, preset) if preset && @post.image.attached?
      redirect_to @post, notice: t("flash.posted")
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
      redirect_to edit_post_path(post), notice: t("flash.shared_into_draft")
    else
      redirect_to new_post_path, alert: t("flash.draft_failed")
    end
  end

  private

  # postable_by? reads bans before privacy, so a community that banned this
  # account never appears as somewhere to send the post.
  def crosspost_targets_for(post)
    return [] if Current.user.blank?

    taken = [ post.community_id, post.crossposted_from&.community_id ].compact +
            (post.crossposted_from || post).crossposts.pluck(:community_id)
    Community.where.not(id: taken.uniq).order(:name).limit(50)
             .select { |community| community.postable_by?(Current.user) }
             .map { |community| [ community.name, community.slug ] }
  end

  def set_post
    @post = find_by_slug_or_id(Post.includes(:user, :community), params[:id])
    # A moderator-removed post is gone for everyone, including via direct link.
    raise ActiveRecord::RecordNotFound if @post&.removed_at?
  end

  def render_members_only
    render template: "shared/members_only", status: :forbidden
  end

  def authorize_owner
    return if Current.user == @post.user

    redirect_to @post, alert: t("shared.flash.not_authorized")
  end

  def set_community
    @community = Community.find_by(id: params[:community_id])
  end

  def post_params
    params.require(:post).permit(:title, :content, :community_id, :anonymous, :image, :video, :audio, :preset, :flair, :nearby)
  end

  # What is left of the Live layer, and the only part of it the front page did
  # not already have.
  #
  # /live was a separate Jodel-shaped surface, but its posts were never a
  # separate pool: they are ordinary rows in `posts`, Brgen::HomeFeed applies no
  # geo exclusion, and Post#author_name already renders a geo-stamped post as
  # "anon" wherever it appears. The Live page was a radius-filtered, locally
  # vote-ranked *view* of the same feed, plus this one compose step. So folding
  # the surface into the front page costs nothing except the stamp, which moves
  # here.
  #
  # Opt-in, and only offered to someone who has already shared coordinates —
  # attaching a location to a post because the author happened to have GPS on
  # would be a privacy change made silently. stamp_live_location! coarsens to
  # ~1km (LIVE_LOCATION_PRECISION) so it marks an area, not a doorway.
  def stamp_nearby!
    return unless ActiveModel::Type::Boolean.new.cast(post_params[:nearby])

    user = Current.user
    return unless user&.latitude.present? && user.longitude.present?

    @post.stamp_live_location!(lat: user.latitude, lng: user.longitude)
  end

  # A restricted community lets the whole city read it and only members post;
  # a private one lets neither. Enforced here rather than only in the view,
  # because a hidden form is not a permission check.
  def enforce_community_posting_rules
    target = @community || Community.find_by(id: post_params[:community_id])
    return if target.blank? || target.postable_by?(Current.user)

    redirect_to(target.readable_by?(Current.user) ? community_path(target) : communities_path,
                alert: t("flash.community.members_only"))
  end

  def share_title
    params[:title].presence || params[:text].presence || params[:url].presence || "Shared draft"
  end

  def share_content
    [ params[:text].presence, params[:url].presence ].compact.join("\n\n")
  end
end
