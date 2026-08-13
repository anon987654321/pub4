# frozen_string_literal: true

class CommunitiesController < ApplicationController
  include Shared::LiveSearchable

  before_action :require_real_user, only: %i[new create edit update destroy]
  before_action :set_community, only: %i[show edit update destroy]
  before_action :authorize_owner, only: %i[edit update destroy]

  def index
    # A private community is not listed to people who are not in it.
    scope = Community.visible_to(Current.user).popular.includes(:user)
    scope = apply_live_search(scope, columns: %w[name description], vertical: "communities") if live_search_query.present?
    @pagy, @communities = pagy(scope)
    finish_live_search(partial: "communities/live_search_results")
  end

  # Same preload set and pagination as PostsController#index and
  # HomeController#index, which this had drifted from. It preloaded :user and
  # :votes but not :community or the image attachment, and it paginated nothing
  # — so it rendered every post a community has ever had, and each one cost a
  # community lookup plus an ActiveStorage attachment and blob lookup for the
  # `post.image.attached?` in shared/_post_card.
  #
  # Measured over 2,584 logged requests on 2026-08-01: 816 queries and a 3.5s
  # p50, with a 110s worst case — the slowest endpoint in the app by both.
  def show
    # Reading and posting are separate questions, and this is the reading one.
    # Restricted communities are readable by the whole city; private ones are
    # not, and a hidden link is not a permission check.
    unless @community.readable_by?(Current.user)
      redirect_to communities_path, alert: t("flash.community.members_only")
      return
    end

    scope = @community.posts.hot.with_attached_image.includes(:user, :community, :votes)
    scope = scope.where(flair: params[:flair]) if params[:flair].present?
    @flair = params[:flair]
    @pagy, @posts = pagy(scope)
    @other_communities = Community.visible_to(Current.user).popular.where.not(id: @community.id).limit(6)
    @moderator = @community.moderator?(Current.user) || @community.owner?(Current.user)
  end

  def new
    @community = Community.new
  end

  def create
    @community = Community.new(community_params)
    @community.user = Current.user
    if @community.save
      # The creator is the owner, and owner is a membership row rather than only
      # communities.user_id — otherwise the moderator list is empty on day one
      # and there is nobody to appoint from.
      @community.community_memberships.create!(user: Current.user, role: "owner")
      redirect_to @community, notice: t("flash.community_created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @community.update(community_params)
      redirect_to @community, notice: t("flash.community_updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @community.destroy
    redirect_to communities_path, notice: t("flash.community_removed")
  end

  private

  # `user` is preloaded because the header reads @community.user, and
  # strict_loading_by_default raises on that lazily — the page rendered for
  # guests and raised for every signed-in visitor, the same shape as the tv
  # video page.
  def set_community
    @community = Community.includes(:user).find(params[:id])
  end

  def authorize_owner
    # user_id, not user: @community comes from Community.find(params[:id]) with
    # nothing preloaded, and strict_loading_by_default raises on the association
    # read before the comparison happens. See comments_controller, same bug.
    #
    # Moderators may edit — rules and flair are the things a mod team maintains
    # — but only an owner may delete the place.
    return if @community.owner?(Current.user)
    return if action_name != "destroy" && @community.moderator?(Current.user)

    redirect_to @community, alert: t("shared.flash.not_authorized")
  end

  def community_params
    params.require(:community).permit(:name, :description, :rules, :privacy, :flairs, :icon, :banner)
  end
end
