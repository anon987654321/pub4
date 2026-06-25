# frozen_string_literal: true

class ComicStripsController < ApplicationController
  allow_unauthenticated_access only: %i[index show]
  before_action :set_comic_strip, only: %i[show]

  def index
    scope = ComicStrip.includes(:user).order(created_at: :desc)
    @pagy, @comic_strips = pagy(scope)
  end

  def show
    @comic_strip.refresh_status!
  end

  def create
    require_authentication
    @comic_strip = Current.user.comic_strips.build(comic_strip_params)

    if @comic_strip.save
      GenerateComicStripJob.perform_later(@comic_strip.id)
      redirect_to @comic_strip, notice: "Generating your comic strip…"
    else
      redirect_to root_path, alert: "Could not start generation."
    end
  end

  private

  def set_comic_strip
    @comic_strip = ComicStrip.find(params[:id])
  end

  def comic_strip_params
    params.require(:comic_strip).permit(:prompt, :style)
  end
end