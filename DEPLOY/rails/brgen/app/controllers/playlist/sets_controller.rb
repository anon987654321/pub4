# frozen_string_literal: true

module Playlist
  class SetsController < ApplicationController
    include Shared::LiveSearchable

    before_action :set_set, only: %i[show edit update destroy]
    before_action :authorize_owner_or_editor, only: %i[edit update destroy]

    def index
      scope = Playlist::Set.publicly_listed
      filters = { genre: params[:genre], artist: params[:artist] }.compact
      scope = apply_live_search(scope, columns: %w[name description], vertical: "playlist", filters: filters)
      scope = scope.with_track_facets(genre: params[:genre], artist: params[:artist])
      @pagy, @sets = pagy(scope.order(created_at: :desc))
      @genres = Playlist::Track.where.not(genre: [nil, ""]).distinct.order(:genre).pluck(:genre)
      @artists = Playlist::Track.where.not(artist: [nil, ""]).distinct.order(:artist).pluck(:artist)

      render_live_search(collection: @sets, partial: "playlist/sets/set") if request.format.turbo_stream?
    end

    def show
      @set_tracks = @set.set_tracks.includes(:track).order(:position)
      @dilla_sketches = @set.dilla_sketches.recent.includes(:user)
    end

    def new
      @set = Playlist::Set.new
    end

    def create
      @set = Playlist::Set.new(set_params)
      @set.user = current_user if respond_to?(:current_user, true)

      if @set.save
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
      params.expect(:set => [:name, :description, :privacy, :collaborative])
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