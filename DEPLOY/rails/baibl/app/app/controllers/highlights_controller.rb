class HighlightsController < ApplicationController
  before_action :require_authentication

  def create
    verse = Verse.find(params[:verse_id])
    @highlight = Current.user.highlights.find_or_initialize_by(verse: verse)
    @highlight.update!(color: params[:color] || "yellow")
    respond_to do |format|
      format.turbo_stream
      format.json { render json: { status: "ok" } }
    end
  end

  def destroy
    @highlight = Current.user.highlights.find(params[:id])
    @highlight.destroy!
    respond_to do |format|
      format.turbo_stream
      format.json { render json: { status: "ok" } }
    end
  end
end
