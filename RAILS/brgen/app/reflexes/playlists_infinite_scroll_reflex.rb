# frozen_string_literal: true

class PlaylistsInfiniteScrollReflex < Shared::InfiniteScrollReflex
  def load_more
    @pagy, @playlists = pagy(playlists_scope, page: page, request:)
    super
  end

  private

  def page_html
    @playlists.map { |playlist| render(partial: "playlist/playlists/row", locals: { playlist: }) }.join
  end

  def playlists_scope
    Playlist::Playlist.public_playlists.popular.includes(:user)
  end
end
