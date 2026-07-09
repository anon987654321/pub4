# frozen_string_literal: true

module Playlist
  class ImportsController < BaseController
    before_action :require_user_session
    before_action :set_playlist

    def create
      authorize_editor!
      return if performed?

      results = Playlist::TrackImportService.new(user: Current.user, playlist: @playlist).call(params[:urls])
      redirect_to playlist_playlist_path(@playlist), notice: "#{results.size} track imports queued"
    end

    private

    def set_playlist
      @playlist = Playlist::Playlist.find(params[:playlist_id])
    end

    def authorize_editor!
      return if Current.user == @playlist.user
      return if @playlist.collaborations.exists?(user: Current.user, role: %w[owner editor])

      redirect_to playlist_playlist_path(@playlist), alert: "Not allowed"
    end
  end
end
