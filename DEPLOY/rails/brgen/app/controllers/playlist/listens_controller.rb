# frozen_string_literal: true

class Playlist::ListensController < Playlist::BaseController
  def create
    track = Playlist::Track.find(params[:track_id])
    Playlist::Listen.create!(user: Current.user, track: track)
    render json: { ok: true }
  end
end
