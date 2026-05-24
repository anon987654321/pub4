# frozen_string_literal: true

module Playlist
  class TimestampedCommentsController < ApplicationController
    before_action :set_track

    def create
      comment = @track.timestamped_comments.build(comment_params)
      comment.user = current_user if respond_to?(:current_user, true)
      comment.save!

      respond_to do |format|
        format.html { redirect_to playlist_track_path(@track) }
        format.turbo_stream
        format.json { render json: { id: comment.id }, status: :created }
      end
    end

    private

    def set_track
      @track = Playlist::Track.find(params[:track_id])
    end

    def comment_params
      params.require(:timestamped_comment).permit(:body, :timestamp_seconds)
    end
  end
end
