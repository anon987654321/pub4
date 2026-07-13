# frozen_string_literal: true

module Playlist
  class SetsController < ApplicationController
    include Shared::LiveSearchable

    before_action :set_set, only: %i[show edit update destroy]
    before_action :authorize_owner_or_editor, only: %i[edit update destroy]

    def index
      scope = Playlist::Set.publicly_listed
      if live_search_query.present?
        set_ids = apply_live_search(scope, columns: %w[name description], vertical: "playlist").pluck(:id)
        track_ids = Playlist::Track.where("name LIKE :q OR artist LIKE :q", q: "%#{ActiveRecord::Base.sanitize_sql_like(live_search_query)}%").pluck(:playlist_set_id)
        scope = scope.where(id: (set_ids + track_ids).uniq)
      end
      @pagy, @sets = pagy(scope)
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
      @set.user = current_user if respond_to?(:current_user, true)

      if @set.save
        @set.record_activity!("PlaylistSetCreated", actor: Current.user, source_vertical: "playlist")
        redirect_to playlist_set_path(@set), notice: t("playlist.set_created", default: "Set created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @set.update(set_params)
        redirect_to playlist_set_path(@set), notice: t("playlist.set_updated", default: "Set updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @set.destroy
      redirect_to playlist_sets_path, notice: t("playlist.set_deleted", default: "Set removed")
    end

    private

    def set_set
      @set = Playlist::Set.find(params[:id])
    end

    def set_params
      params.require(:set).permit(:name, :description, :privacy, :collaborative)
    end

    def authorize_owner_or_editor
      user = Current.user || (respond_to?(:current_user) ? current_user : nil)
      return if user == @set.user
      collab = @set.collaborations.find_by(user: user)
      return if collab && %w[owner editor].include?(collab.role)
      redirect_to(playlist_set_path(@set), alert: "Not allowed")
    end
  end
end
