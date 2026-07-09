# frozen_string_literal: true

class ComicStripsController < ApplicationController
  include Shared::LiveSearchable

  allow_unauthenticated_access only: %i[index show]
  before_action :set_comic_strip, only: %i[show]

  def index
    scope = ComicStrip.includes(:user).order(created_at: :desc)
    scope = apply_live_search(scope, columns: %w[prompt style status], vertical: "comic_strips") if live_search_query.present?
    @pagy, @comic_strips = pagy(scope)
    finish_live_search(partial: "comic_strips/live_search_results")
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