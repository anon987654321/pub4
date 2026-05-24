# frozen_string_literal: true

module Playlist
  class AudioVersionsController < ApplicationController
    before_action :set_track

    def create
      @track.replace_audio!(params.require(:audio_file), actor: current_user_if_available)
      redirect_to playlist_track_path(@track), notice: t("playlist.audio_replaced", default: "Audio replaced")
    end

    private

    def set_track
      @track = Playlist::Track.find(params[:track_id])
    end

    def current_user_if_available
      current_user if respond_to?(:current_user, true)
    end
  end
end
