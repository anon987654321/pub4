# frozen_string_literal: true

module Playlist
  class HostedTracksController < BaseController
    allow_unauthenticated_access only: %i[index show]
    before_action :require_real_user, except: %i[index show]
    before_action :set_track, only: %i[show edit update destroy]
    before_action :authorize_owner!, only: %i[edit update destroy]

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
      files = Array(params.dig(:track, :audio_file)).compact
      if files.size > 1
        created = files.map do |file|
          t = Playlist::Track.new(track_params.except(:audio_file))
          t.user = Current.user if t.respond_to?(:user=)
          t.audio_file.attach(file)
          t.save ? t : nil
        end.compact
        redirect_to playlist_hosted_tracks_path, notice: "#{created.size} tracks uploaded (bulk like Whyp)"
      else
        @track = Playlist::Track.new(track_params.except(:audio_file))
        @track.user = Current.user if @track.respond_to?(:user=)
        @track.audio_file.attach(files.first) if files.any?
        @track.artwork.attach(params[:track][:artwork]) if params.dig(:track, :artwork).present?

        if @track.save
          redirect_to playlist_hosted_track_path(@track), notice: t("playlist.track_created", default: "Track uploaded")
        else
          render :new, status: :unprocessable_entity
        end
      end
    end

    def edit
    end

    def update
      if params.dig(:track, :audio_file).present?
        @track.replace_audio!(params[:track][:audio_file], actor: Current.user)
      end
      if @track.update(track_params.except(:audio_file))
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

    def authorize_owner!
      return unless @track.respond_to?(:user)
      return if @track.user == Current.user

      redirect_to playlist_hosted_tracks_path, alert: t("playlist.not_allowed", default: "Not allowed")
    end
  end
end
