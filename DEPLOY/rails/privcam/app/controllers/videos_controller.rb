# frozen_string_literal: true

class VideosController < ApplicationController
  allow_unauthenticated_access only: %i[index show]

  def index
    scope = Video.includes(:user).order(created_at: :desc)
    @pagy, @videos = pagy(scope)
  end

  def show
    @video = Video.includes(:user, comments: :user).find(params[:id])
    @comments = @video.comments.order(created_at: :asc)
  end
end