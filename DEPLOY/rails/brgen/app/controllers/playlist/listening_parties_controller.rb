# frozen_string_literal: true

class Playlist::ListeningPartiesController < Playlist::BaseController
    before_action :require_real_user
    before_action :set_set
    before_action :set_party, only: %i[show update destroy]

    def show
      @messages = @party.party_messages.includes(:user).chronological.limit(100)
      @tracks = @set.tracks.order(:position)
    end

    def create
      @party = @set.build_listening_party(host: Current.user, status: "active")
      first_track = @set.tracks.order(:position).first
      @party.current_track = first_track
      @party.save!
      redirect_to playlist_set_listening_party_path(@set), notice: "Listening party started"
    end

    def update
      track = @set.tracks.find_by(id: params[:track_id]) if params[:track_id].present?
      @party.sync!(track: track || @party.current_track, position_seconds: params[:position_seconds])
      head :ok
    end

    def destroy
      @party.end!
      redirect_to playlist_set_path(@set), notice: "Party ended"
    end

    private

    def set_set
      @set = Playlist::Set.find(params[:set_id])
    end

    def set_party
      @party = @set.listening_party || raise(ActiveRecord::RecordNotFound)
    end
  end