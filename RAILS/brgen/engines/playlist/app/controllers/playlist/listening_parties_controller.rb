# frozen_string_literal: true

class Playlist::ListeningPartiesController < Playlist::BaseController
    before_action :require_user_session
    before_action :set_set
    before_action :set_party,     only: %i[show update destroy]
    before_action :require_host!, only: %i[update destroy]

    def show
      unless party_viewer_allowed?
        redirect_to set_path(@set), alert: t("flash.playlist.party_code_required")
        return
      end
      @messages = @party.party_messages.includes(:user).chronological.limit(100)
      @tracks = @set.tracks.order(:position)
    end

    def create
      unless set_owner_or_editor?
        redirect_to set_path(@set), alert: t("shared.flash.not_authorized")
        return
      end
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
      raise ActiveRecord::RecordNotFound unless set_visible_to_viewer?
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

    def set_owner_or_editor?
      Current.user && (
        @set.user_id == Current.user.id ||
        @set.collaborations.exists?(user_id: Current.user.id, role: %w[owner editor])
      )
    end

    def set_party
      @party = @set.listening_party || raise(ActiveRecord::RecordNotFound)
    end

    def require_host!
      unless Current.user && @party.host_id == Current.user.id
        redirect_to(set_listening_party_path(@set), alert: t("shared.flash.not_authorized"))
      end
    end

    def party_viewer_allowed?
      return true if Current.user && @party.host_id == Current.user.id
      return true if Array(session[:listening_party_ok]).include?(@party.id)

      code = params[:code].to_s.upcase
      return false unless code.present? && code == @party.join_code.to_s.upcase

      session[:listening_party_ok] = Array(session[:listening_party_ok]) | [@party.id]
      true
    end
  end
