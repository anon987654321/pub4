# frozen_string_literal: true

class CommunitiesController < ApplicationController
  include Shared::LiveSearchable

  before_action :require_real_user, only: [ :new, :create ]
  before_action :set_community,     only: [ :show ]

  def index
    scope = Community.popular.includes(:user)
    scope = apply_live_search(scope, columns: %w[name description], vertical: "communities") if live_search_query.present?
    @communities = scope.limit(100)
    finish_live_search(partial: "communities/live_search_results")
  end

  def show
    @posts = @community.posts.hot.includes(:user, :votes)
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

  private

  def set_community    = @community = Community.find(params[:id])
  def community_params = params.require(:community).permit(:name, :description)
end
