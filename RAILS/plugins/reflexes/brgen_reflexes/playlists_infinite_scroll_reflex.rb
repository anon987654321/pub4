# frozen_string_literal: true

class PlaylistsInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "playlist/playlists/row", as: :playlist, wrap_in: :li

  private

  def scope
    Playlist::Playlist.public_playlists.popular.includes(:user)
  end
end
