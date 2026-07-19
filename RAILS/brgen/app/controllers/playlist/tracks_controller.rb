# frozen_string_literal: true

class Playlist::TracksController < Playlist::BaseController
  before_action :require_real_user
  before_action :set_container
  before_action :authorize_editor!

  def create
    track = Playlist::Track.find_or_create_by!(title: params.dig(:playlist_track, :title),
                                               artist: params.dig(:playlist_track, :artist),
                                               source_url: params.dig(:playlist_track, :source_url)) do |record|
      record.assign_attributes(track_params.except(:title, :artist))
    end

    if @set
      @set.add_track!(track, user: Current.user)
      redirect_to playlist_set_path(@set), notice: "Track added"
    else
      @playlist.add_track!(track, user: Current.user)
      redirect_to playlist_playlist_path(@playlist), notice: "Track added"
    end
  end

  def destroy
    if @set
      @set.set_tracks.find(params[:id]).destroy
      redirect_to playlist_set_path(@set)
    else
      @playlist.playlist_tracks.find(params[:id]).destroy
      redirect_to playlist_playlist_path(@playlist)
    end
  end

  private

  def set_container
    if params[:set_id]
      @set = Playlist::Set.find(params[:set_id])
    elsif params[:playlist_id]
      @playlist = ::Playlist::Playlist.find(params[:playlist_id])
    else
      redirect_to playlist_playlists_path
    end
  end

  def track_params
    params.require(:playlist_track).permit(:title, :artist, :album, :duration_seconds, :source_type, :source_url, :genre, :privacy, :expires_at)
  end

  def authorize_editor!
    target = @set || @playlist
    return if target&.user == Current.user

    collab = target&.collaborations&.find_by(user: Current.user)
    return if collab && %w[owner editor].include?(collab.role)

    target_path = target ? playlist_target_path(target) : playlist_playlists_path
    redirect_to target_path, alert: "Not allowed"
  end

  def playlist_target_path(target)
    target.is_a?(Playlist::Set) ? playlist_set_path(target) : playlist_playlist_path(target)
  end
end
