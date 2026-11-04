# frozen_string_literal: true

class Playlist::ListensController < Playlist::BaseController
  before_action :require_user_session, only: :create

  def create
    track = Playlist::Track.find(params[:track_id])
    raise ActiveRecord::RecordNotFound unless track.visible_to?(Current.user) || track.privacy.to_s == "unlisted"

    render json: { ok: true, counted: Playlist::Listen.record(user: Current.user, track:) }
  end
end
