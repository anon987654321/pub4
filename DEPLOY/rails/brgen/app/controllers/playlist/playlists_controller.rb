# frozen_string_literal: true

class Playlist::PlaylistsController < Playlist::BaseController
  allow_unauthenticated_access only: %i[index show]
  before_action :set_playlist, only: %i[show edit update destroy]
  before_action :authorize_owner_or_editor, only: %i[edit update destroy]

  def index
    @pagy, @playlists = pagy(Playlist::Playlist.public_playlists.popular.includes(:user))
  end

  def show
    @tracks = @playlist.playlist_tracks.includes(:track)
    @dilla_sketches = @playlist.dilla_sketches.recent.includes(:user)
  end

  def new
    @playlist = Playlist::Playlist.new
  end

  def create
    @playlist = Current.user.playlist_playlists.build(playlist_params)
    @playlist.save ?
      redirect_to(playlist_playlist_path(@playlist), notice: "Playlist created") :
      render(:new, status: :unprocessable_entity)
  end

  def edit; end

  def update
    @playlist.update(playlist_params) ?
      redirect_to(playlist_playlist_path(@playlist)) :
      render(:edit, status: :unprocessable_entity)
  end

  def destroy
    @playlist.destroy
    redirect_to playlist_playlists_path
  end

  private

  def set_playlist
    @playlist = Playlist::Playlist.find(params[:id])
  end

  def playlist_params
    params.expect(:playlist_playlist => [:name, :description, :public_access, :collaborative])
  end

  def authorize_owner_or_editor
    return if Current.user == @playlist.user
    collab = @playlist.collaborations.find_by(user: Current.user)
    return if collab && %w[owner editor].include?(collab.role)
    redirect_to(playlist_playlist_path(@playlist), alert: "Not allowed")
  end
end
