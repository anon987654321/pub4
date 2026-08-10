# frozen_string_literal: true

class CommunitiesController < ApplicationController
  include Shared::LiveSearchable

  before_action :require_real_user, only: %i[new create edit update destroy]
  before_action :set_community, only: %i[show edit update destroy]
  before_action :authorize_owner, only: %i[edit update destroy]

  def index
    scope = Community.popular.includes(:user)
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
    scope = @community.posts.hot.with_attached_image.includes(:user, :community, :votes)
    @pagy, @posts = pagy(scope)
  end

  def new
    @community = Community.new
  end

  def create
    @community = Community.new(community_params)
    @community.user = Current.user
    if @community.save
      redirect_to @community, notice: "Community created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @community.update(community_params)
      redirect_to @community, notice: "Community updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @community.destroy
    redirect_to communities_path, notice: "Community removed."
  end

  private

  def set_community
    @community = Community.find(params[:id])
  end

  def authorize_owner
    # user_id, not user: @community comes from Community.find(params[:id]) with
    # nothing preloaded, and strict_loading_by_default raises on the association
    # read before the comparison happens. See comments_controller, same bug.
    return if Current.user && Current.user.id == @community.user_id

    redirect_to @community, alert: "Not allowed"
  end

  def community_params
    params.require(:community).permit(:name, :description)
  end
end
