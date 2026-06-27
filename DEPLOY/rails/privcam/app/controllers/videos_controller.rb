# frozen_string_literal: true

class VideosController < ApplicationController
  include Shared::LiveSearchable

  allow_unauthenticated_access only: %i[index show]

  def index
    scope = Video.includes(:user).order(created_at: :desc)
    scope = apply_live_search(scope, columns: %w[title description], vertical: "videos") if live_search_query.present?
    @pagy, @videos = pagy(scope)
    finish_live_search(partial: "videos/live_search_results")
  end

  def show
    @video = Video.includes(:user, comments: :user).find(params[:id])
    @comments = @video.comments.order(created_at: :asc)
  end
end