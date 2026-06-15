# frozen_string_literal: true

module Playlist
  class HostedTracksController < Playlist::BaseController
    include Shared::LiveSearchable

    allow_unauthenticated_access only: %i[index show]
    before_action :set_track, only: %i[show edit update destroy]

    def index
      scope = Playlist::Track.publicly_visible.unexpired
      filters = { genre: params[:genre], artist: params[:artist] }.compact
      scope = apply_live_search(scope, columns: %w[title artist album genre], vertical: "playlist", filters: filters)
      scope = scope.where(genre: params[:genre]) if params[:genre].present?
      scope = scope.where(artist: params[:artist]) if params[:artist].present?
      @pagy, @tracks = pagy(scope.recent)
      @genres = Playlist::Track.where.not(genre: [nil, ""]).distinct.order(:genre).pluck(:genre)
      @artists = Playlist::Track.where.not(artist: [nil, ""]).distinct.order(:artist).pluck(:artist)

      render_live_search(collection: @tracks, partial: "playlist/hosted_tracks/track") if request.format.turbo_stream?
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
      params.expect(:track => [:title, :artist, :album, :duration_seconds, :source_type, :source_url, :genre, :privacy, :expires_at])
    end
  end
end