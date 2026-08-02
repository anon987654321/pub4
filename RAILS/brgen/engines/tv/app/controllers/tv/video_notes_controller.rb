# frozen_string_literal: true

module Tv
  class VideoNotesController < ApplicationController
    before_action :set_video

    def create
      @video_note = @video.video_notes.build(video_note_params)
      @video_note.user = current_user if respond_to?(:current_user, true)
      @video_note.save!

      respond_to do |format|
        format.html { redirect_to video_path(@video) }
        format.turbo_stream
        format.json { render json: { id: @video_note.id }, status: :created }
      end
    end

    private

    def set_video
      @video = Tv::Video.find(params[:video_id])
    end

    def video_note_params
      params.require(:video_note).permit(:body, :timestamp)
    end
  end
end
