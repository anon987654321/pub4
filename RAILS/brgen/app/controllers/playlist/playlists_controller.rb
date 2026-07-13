# frozen_string_literal: true

class Playlist::PlaylistsController < Playlist::BaseController
  allow_unauthenticated_access only: %i[index show]
  before_action :set_playlist, only: %i[show embed edit update destroy]
  before_action :authorize_owner_or_editor, only: %i[edit update destroy]

  def index
    @pagy, @playlists = pagy(Playlist::Playlist.public_playlists.popular.includes(:user))
    @trending_playlists = Playlist::Playlist.city_trending.includes(:user).limit(12)
  end

  def show
    @tracks = playlist_tracks
    @dilla_sketches = @playlist.dilla_sketches.recent.includes(:user)
    # Group for whyp-like per-track timestamp comments on waveform
    @track_comments = @tracks.each_with_object({}) do |pt, h|
      tr = pt.track
      h[tr.id] = tr.timestamped_comments.chronological.map { |c| { time: (c.timestamp_seconds || 0).to_f, text: c.body } }
    end
    active = @tracks.first&.track
    @comments = active ? (@track_comments[active.id] || []) : []
  end

  def embed
    @tracks = playlist_tracks
    @embed_options = {
      color: params[:color] || "#00d4ff",
      show_artwork: params[:show_artwork] != "0",
      compact: params[:compact] == "1",
      hide_branding: params[:hide_branding] == "1"
    }
    render layout: false
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
    @playlist = Playlist::Playlist.includes(:user).find(params[:id])
  end

  def playlist_params
    params.require(:playlist_playlist).permit(:name, :description, :public_access, :collaborative)
  end

  def playlist_tracks
    @playlist.playlist_tracks.joins(:track).merge(Playlist::Track.unexpired).includes(:track)
  end

  def authorize_owner_or_editor
    return if Current.user == @playlist.user
    collab = @playlist.collaborations.find_by(user: Current.user)
    return if collab && %w[owner editor].include?(collab.role)
    redirect_to(playlist_playlist_path(@playlist), alert: "Not allowed")
  end
end
