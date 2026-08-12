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
      redirect_to set_path(@set), notice: t("flash.playlist.track_added")
    else
      @playlist.add_track!(track, user: Current.user)
      redirect_to playlist_path(@playlist), notice: t("flash.playlist.track_added")
    end
  end

  def destroy
    if @set
      @set.set_tracks.find(params[:id]).destroy
      redirect_to set_path(@set)
    else
      @playlist.playlist_tracks.find(params[:id]).destroy
      redirect_to playlist_path(@playlist)
    end
  end

  private

  def set_container
    if params[:set_id]
      @set = Playlist::Set.find(params[:set_id])
    elsif params[:playlist_id]
      @playlist = find_by_slug_or_id(::Playlist::Playlist, params[:playlist_id])
    else
      redirect_to playlists_path
    end
  end

  def track_params
    params.require(:playlist_track).permit(:title, :artist, :album, :duration_seconds, :source_type, :source_url, :genre, :privacy, :expires_at)
  end

  # user_id, not user: @set and @playlist both come from finders with nothing
  # preloaded, and strict_loading_by_default raises on the association read
  # before the comparison — so the owner's own edit failed here too. The
  # collaboration lookup below is a query rather than a lazy read, so it was
  # never the part that broke.
  def authorize_editor!
    target = @set || @playlist
    return if Current.user && target&.user_id == Current.user.id

    collab = target&.collaborations&.find_by(user: Current.user)
    return if collab && %w[owner editor].include?(collab.role)

    target_path = target ? target_path(target) : playlists_path
    redirect_to target_path, alert: t("shared.flash.not_authorized")
  end

  def target_path(target)
    target.is_a?(Playlist::Set) ? set_path(target) : playlist_path(target)
  end
end
