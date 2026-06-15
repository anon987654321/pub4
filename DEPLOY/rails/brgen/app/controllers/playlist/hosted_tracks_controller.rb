# frozen_string_literal: true

module Playlist
  class HostedTracksController < BaseController
    allow_unauthenticated_access only: %i[index show]
    before_action :set_track, only: %i[show edit update destroy]

    def index
      @tracks = Playlist::Track.publicly_visible.unexpired.recent.limit(100)
    end

    def show
      @comments = @track.timestamped_comments.chronological.limit(200)
    end

    def new
      @track = Playlist::Track.new
    end

    def create
      @track = Playlist::Track.new(track_params)
      @track.audio_file.attach(params[:track][:audio_file]) if params.dig(:track, :audio_file).present?
      @track.artwork.attach(params[:track][:artwork]) if params.dig(:track, :artwork).present?

      if @track.save
        redirect_to playlist_hosted_track_path(@track), notice: t("playlist.track_created", default: "Track uploaded")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @track.update(track_params)
        redirect_to playlist_hosted_track_path(@track), notice: t("playlist.track_updated", default: "Track updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @track.destroy
      redirect_to playlist_hosted_tracks_path, notice: t("playlist.track_deleted", default: "Track removed")
    end

    private

    def set_track
      @track = Playlist::Track.find(params[:id])
    end

    def track_params
      params.require(:track).permit(:title, :artist, :album, :duration_seconds, :source_type, :source_url, :genre, :privacy, :expires_at)
    end
  end
end
