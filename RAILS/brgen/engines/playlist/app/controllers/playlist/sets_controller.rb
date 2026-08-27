# frozen_string_literal: true

# Compact style, like every other controller in this directory, and not
# `module Playlist; class ...`. Inside that nesting the constant `Playlist`
# resolves to the Playlist::Playlist *model* first, so `Playlist::Set` became
# `Playlist::Playlist::Set` and both index actions raised NameError.
class Playlist::SetsController < ApplicationController
  include Shared::LiveSearchable

  before_action :require_user_session, only: %i[new create]
  before_action :set_set, only: %i[show edit update destroy]
  before_action :authorize_owner_or_editor, only: %i[edit update destroy]

  def index
    scope = Playlist::Set.publicly_listed
    if live_search_query.present?
      set_ids = apply_live_search(scope, columns: %w[name description], vertical: "playlist").pluck(:id)
      # playlist_tracks has `title`, not `name`, and carries no playlist_set_id —
      # sets reach tracks through playlist_set_tracks. The previous raw query
      # named both missing columns, so any non-blank search raised
      # "no such column: playlist_set_id".
      matching_tracks = Playlist::Track
                        .where("title LIKE :q OR artist LIKE :q", q: "%#{ActiveRecord::Base.sanitize_sql_like(live_search_query)}%")
                        .select(:id)
      track_set_ids = Playlist::SetTrack.where(playlist_track_id: matching_tracks).pluck(:playlist_set_id)
      scope = scope.where(id: (set_ids + track_set_ids).uniq)
    end
    @pagy, @sets = pagy(scope)
    # One grouped count for the page, through the join table sets reach tracks
    # by. The card asked each set for tracks.count — a COUNT per card, and
    # .count would query even if the association had been preloaded.
    @track_counts = Playlist::SetTrack.where(playlist_set_id: @sets.map(&:id))
                                      .group(:playlist_set_id).count
    finish_live_search(partial: "playlist/sets/live_search_results")
  end

  def show
    @set_tracks = @set.set_tracks.includes(:track)
    @tracks = @set.tracks
    @dilla_sketches = @set.dilla_sketches.recent.includes(:user)
    # Prepare full waveform player + per-track timestamp comments on collection
    @track_comments = @tracks.each_with_object({}) do |tr, h|
      h[tr.id] = tr.timestamped_comments.chronological.map { |c| { time: (c.timestamp_seconds || 0).to_f, text: c.body } }
    end
    @comments = @tracks.first ? (@track_comments[@tracks.first.id] || []) : []
  end

  def new
    @set = Playlist::Set.new
  end

  def create
    @set = Playlist::Set.new(set_params)
    @set.user = Current.user

    if @set.save
      @set.record_activity!("PlaylistSetCreated", actor: Current.user, source_vertical: "playlist")
      redirect_to set_path(@set), notice: t("playlist.set_created", default: "Set created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @set.update(set_params)
      redirect_to set_path(@set), notice: t("playlist.set_updated", default: "Set updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @set.destroy
    redirect_to sets_path, notice: t("playlist.set_deleted", default: "Set removed")
  end

  private

  def set_set
    @set = Playlist::Set.find(params[:id])
    return if set_visible_to_viewer?

    raise ActiveRecord::RecordNotFound
  end

  def set_visible_to_viewer?
    case @set.privacy.to_s
    when "", "public", "unlisted" then true
    when "private"
      Current.user && (
        @set.user_id == Current.user.id ||
        @set.collaborations.exists?(user_id: Current.user.id)
      )
    else true
    end
  end

  # The form scope is the model's param_key, "playlist_set" -- same as
  # PlaylistsController's :playlist_playlist. Requiring :set here meant a
  # submitted form would have raised ParameterMissing, had the form rendered.
  def set_params
    params.require(:set).permit(:name, :description, :privacy, :collaborative)
  end

  def authorize_owner_or_editor
    user = Current.user || (respond_to?(:current_user) ? current_user : nil)
    # user_id, not user — @set is found by id with nothing preloaded and
    # strict_loading_by_default raises on the association read.
    return if user && user.id == @set.user_id
    collab = @set.collaborations.find_by(user: user)
    return if collab && %w[owner editor].include?(collab.role)
    redirect_to(set_path(@set), alert: t("shared.flash.not_authorized"))
  end
end
