# frozen_string_literal: true

module Tv
  class VideoNotesController < Tv::BaseController
    before_action :require_user_session
    before_action :set_video

    def create
      @video_note = @video.video_notes.build(video_note_params.merge(user: Current.user))

      if @video_note.save
        respond_to do |format|
          format.html { redirect_to video_path(@video) }
          format.turbo_stream
          format.json { render json: { id: @video_note.id }, status: :created }
        end
      else
        alert = @video_note.errors.full_messages.to_sentence
        respond_to do |format|
          format.html { redirect_to video_path(@video), alert: }
          format.turbo_stream { head :unprocessable_entity }
          format.json { render json: { errors: @video_note.errors }, status: :unprocessable_entity }
        end
      end
    end

    private

    def set_video
      @video = find_by_slug_or_id(Tv::Video, params[:video_id])
    end

    def video_note_params
      params.require(:video_note).permit(:body, :timestamp)
    end
  end
end
