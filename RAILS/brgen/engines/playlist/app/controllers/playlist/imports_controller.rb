# frozen_string_literal: true

module Playlist
  class ImportsController < BaseController
    before_action :require_user_session
    before_action :set_playlist

    def create
      authorize_editor!
      return if performed?

      results = ::Playlist::TrackImport.new(user: Current.user, playlist: @playlist).call(params[:urls])
      redirect_to playlist_path(@playlist), notice: "#{results.size} track imports queued"
    end

    private

    def set_playlist
      # Absolute constant — nested under module Playlist, relative Playlist::Playlist nests again.
      @playlist = find_by_slug_or_id(::Playlist::Playlist.includes(:user), params[:playlist_id])
    end

    def authorize_editor!
      return if Current.user&.id == @playlist.user_id
      return if @playlist.collaborations.exists?(user: Current.user, role: %w[owner editor])

      redirect_to playlist_path(@playlist), alert: "Not allowed"
    end
  end
end
