# frozen_string_literal: true

# Compact style, like every other controller in this directory, and not
# `module Playlist; class ...`. Inside that nesting the constant `Playlist`
# resolves to the Playlist::Playlist *model* first, so `Playlist::Set` became
# `Playlist::Playlist::Set` and both index actions raised NameError.
class Playlist::HostedTracksController < Playlist::BaseController
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
      redirect_to hosted_tracks_path, notice: t("playlist.tracks_uploaded", count: created.size)
    else
      @track = Playlist::Track.new(track_params.except(:audio_file))
      @track.user = Current.user if @track.respond_to?(:user=)
      @track.audio_file.attach(files.first) if files.any?
      @track.artwork.attach(params[:track][:artwork]) if params.dig(:track, :artwork).present?

      if @track.save
        redirect_to hosted_track_path(@track), notice: t("playlist.track_created")
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
      redirect_to hosted_track_path(@track), notice: t("playlist.track_updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @track.destroy
    redirect_to hosted_tracks_path, notice: t("playlist.track_deleted")
  end

  private

  def set_track
    @track = Playlist::Track.find(params[:id])
    return if track_visible_to_viewer?

    raise ActiveRecord::RecordNotFound
  end

  def track_visible_to_viewer?
    case @track.privacy.to_s
    when "", "public", "unlisted" then true
    when "private" then Current.user && @track.user_id == Current.user.id
    else true
    end
  end

  def track_params
    params.require(:track).permit(:title, :artist, :album, :duration_seconds, :source_type, :source_url, :genre, :privacy, :expires_at)
  end

  # user_id, not user. set_track finds the record with nothing preloaded, and
  # ApplicationRecord sets strict_loading_by_default in every environment, so
  # reading the association raised before the comparison could run — the guard
  # never denied anyone, it failed for everyone, the owner included.
  #
  # The respond_to?(:user) line above it was the tell: a defence placed against
  # a failure that cannot happen, one line above the one that does. respond_to?
  # is true; the read is what raises. Comparing the column needs no preload and
  # cannot raise at all.
  def authorize_owner!
    return if Current.user && @track.user_id == Current.user.id

    redirect_to hosted_tracks_path, alert: t("playlist.not_allowed", default: "Not allowed")
  end
end
