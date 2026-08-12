# frozen_string_literal: true

class Playlist::ListeningPartiesController < Playlist::BaseController
    before_action :require_user_session
    before_action :set_set
    before_action :set_party,     only: %i[show update destroy]
    before_action :require_host!, only: %i[update destroy]

    def show
      @messages = @party.party_messages.includes(:user).chronological.limit(100)
      @tracks = @set.tracks.order(:position)
    end

    def create
      @party = @set.build_listening_party(host: Current.user, status: "active")
      first_track = @set.tracks.order(:position).first
      @party.current_track = first_track
      @party.save!
      redirect_to set_listening_party_path(@set), notice: t("flash.playlist.party_started")
    end

    def update
      track = @set.tracks.find_by(id: params[:track_id]) if params[:track_id].present?
      @party.sync!(track: track || @party.current_track, position_seconds: params[:position_seconds])
      head :ok
    end

    def destroy
      @party.end!
      redirect_to set_path(@set), notice: t("flash.playlist.party_ended")
    end

    private

    def set_set
      @set = Playlist::Set.includes(:listening_party, :tracks).find(params[:set_id])
    end

    def set_party
      @party = @set.listening_party || raise(ActiveRecord::RecordNotFound)
    end

    def require_host!
      redirect_to(set_listening_party_path(@set), alert: t("shared.flash.not_authorized")) unless @party.host == Current.user
    end
  end
