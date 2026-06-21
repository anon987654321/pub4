# frozen_string_literal: true

class HighlightsController < ApplicationController
  before_action :require_authentication

  def create
    verse = Verse.find(params[:verse_id])
    @highlight = Current.user.highlights.find_or_initialize_by(verse: verse)
    @highlight.update!(color: params[:color] || "yellow")
    @highlight.record_activity!("HighlightCreated", source_vertical: "baibl", metadata: { color: @highlight.color })
    respond_to do |format|
      format.turbo_stream
      format.json { render json: { status: "ok" } }
    end
  end

  def destroy
    @highlight = Current.user.highlights.find(params[:id])
    @highlight.record_activity!("HighlightRemoved", source_vertical: "baibl")
    @highlight.destroy!
    respond_to do |format|
      format.turbo_stream
      format.json { render json: { status: "ok" } }
    end
  end
end
