# frozen_string_literal: true

module Playlist
  class SetsController < ApplicationController
    before_action :set_set, only: %i[show edit update destroy]

    def index
      @sets = Playlist::Set.publicly_listed.limit(100)
    end

    def show
      @tracks = @set.tracks
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
      params.require(:set).permit(:name, :description, :privacy, :collaborative)
    end
  end
end
