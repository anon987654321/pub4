# frozen_string_literal: true

class Playlist::PartyMessagesController < Playlist::BaseController
    before_action :require_user_session
    before_action :set_party

    def create
      @message = @party.party_messages.create!(user: Current.user, body: params[:body].to_s.strip)
      redirect_to set_listening_party_path(@party.set), notice: nil
    rescue ActiveRecord::RecordInvalid
      redirect_to set_listening_party_path(@party.set), alert: t("flash.playlist.message_failed")
    end

    private

    def set_party
      set = Playlist::Set.find(params[:set_id])
      @party = set.listening_party || raise(ActiveRecord::RecordNotFound)
      host = Current.user && @party.host_id == Current.user.id
      joined = Array(session[:listening_party_ok]).include?(@party.id)
      raise ActiveRecord::RecordNotFound unless host || joined
    end
  end
