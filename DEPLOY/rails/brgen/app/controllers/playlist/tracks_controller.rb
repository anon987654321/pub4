# frozen_string_literal: true

class Playlist::TracksController < Playlist::BaseController
  before_action :set_container

  def create
    track = Playlist::Track.find_or_create_by!(title: params.dig(:playlist_track, :title),
                                               artist: params.dig(:playlist_track, :artist)) do |record|
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
      @playlist = Playlist::Playlist.find(params[:playlist_id])
    else
      redirect_to playlist_playlists_path
    end
  end

  def track_params
    params.require(:playlist_track).permit(:title, :artist, :album, :duration_seconds, :source_type, :source_url, :genre)
  end
end
