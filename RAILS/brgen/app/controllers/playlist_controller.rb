# frozen_string_literal: true

class PlaylistController < ApplicationController
  def index
    @playlists = [
      { name: "Bergen Beats", tracks: 12, genre: "Electronic" },
      { name: "Norwegian Folk", tracks: 8, genre: "Folk" },
      { name: "Midnight Jazz", tracks: 15, genre: "Jazz" }
    ]
  end
end
