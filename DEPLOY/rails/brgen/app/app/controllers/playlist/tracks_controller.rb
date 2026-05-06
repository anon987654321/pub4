class Playlist::TracksController < Playlist::BaseController
  before_action :set_playlist

  def create
    track = Playlist::Track.find_or_create_by!(title: params.dig(:playlist_track, :title),
                                               artist: params.dig(:playlist_track, :artist)) do |t|
      t.assign_attributes(track_params.except(:title, :artist))
    end
    @playlist.add_track!(track, user: Current.user)
    redirect_to playlist_playlist_path(@playlist), notice: "Track added"
  end

  def destroy
    pt = @playlist.playlist_tracks.find(params[:id])
    pt.destroy
    redirect_to playlist_playlist_path(@playlist)
  end

  private
  def set_playlist  = (@playlist = Playlist::Playlist.find(params[:playlist_id]))
  def track_params  = params.require(:playlist_track).permit(:title, :artist, :album, :duration_seconds, :source_type, :source_url, :genre)
end
