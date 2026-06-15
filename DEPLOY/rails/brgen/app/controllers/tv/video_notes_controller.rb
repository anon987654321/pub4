# frozen_string_literal: true

module Tv
  class VideoNotesController < ApplicationController
    before_action :set_video

    def create
      note = @video.video_notes.build(video_note_params)
      note.user = current_user if respond_to?(:current_user, true)
      note.save!

      respond_to do |format|
        format.html { redirect_to tv_video_path(@video) }
        format.turbo_stream
        format.json { render json: { id: note.id }, status: :created }
      end
    end

    private

    def set_video
      @video = Tv::Video.find(params[:video_id])
    end

    def video_note_params
      params.expect(:video_note => [:body, :timestamp])
    end
  end
end
