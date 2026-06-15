# frozen_string_literal: true
# AN620: Collaborative playlist editing

module Playlist
  class CollaborativeEditor
    def initialize(playlist, user)
      @playlist = playlist
      @user = user
    end

    def add_track(track)
      entry = @playlist.playlist_tracks.create!(track: track, added_by: @user)
      @playlist.broadcast_append_to(@playlist, target: "tracks", partial: "playlist/tracks/track", locals: { track: entry })
      entry
    rescue ActiveRecord::RecordNotUnique
      notify_conflict
      nil
    end

    private

    def notify_conflict
      Turbo::StreamsChannel.broadcast_append_to(@playlist, target: "notifications", html: "<p>Track already added — last write wins.</p>")
    end
  end
end