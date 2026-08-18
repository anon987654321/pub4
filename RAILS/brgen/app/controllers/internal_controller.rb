# frozen_string_literal: true

# Read-only status + reverse-publish for MASTER / local services on the VPS.
class InternalController < ApplicationController
  include Shared::InternalTokenAuth

  def status
    render json: {
      app: "brgen",
      city: Current.try(:city),
      generated_at: Time.now.utc.iso8601,
      marketplace_listings: Marketplace::Listing.count,
      takeaway_open_orders: Takeaway::Order.active.count,
      playlist_tracks: Playlist::Track.count,
      dilla_sketches: Playlist::DillaSketch.count,
      tv_live_streams: Tv::LiveStream.live.count,
      dating_profiles: Dating::Profile.count,
      dilla_engine: Shared::DillaProcessor.available?,
      master_client: Shared::MasterClient.configured?,
    }
  end

  # MASTER tools → brgen: publish a rendered MP3 into a playlist.
  # Multipart: audio file + title + optional playlist_id / user_email
  def dilla_publish
    title = params[:title].to_s.presence || "Dilla render"
    user = find_publish_user
    return render(json: { ok: false, error: "user not found" }, status: :unprocessable_entity) unless user

    upload = params[:audio] || params[:file]
    return render(json: { ok: false, error: "audio missing" }, status: :bad_request) unless upload.respond_to?(:read)

    track = Playlist::Track.create!(
      user: user,
      title: title.truncate(100),
      artist: params[:artist].presence || "MASTER Dilla",
      source_type: "dilla",
      privacy: params[:privacy].presence || "unlisted"
    )
    track.audio_file.attach(
      io: upload.tempfile || StringIO.new(upload.read),
      filename: upload.original_filename.presence || "dilla.mp3",
      content_type: upload.content_type.presence || "audio/mpeg"
    )

    if params[:playlist_id].present?
      pl = Playlist::Playlist.find_by(id: params[:playlist_id])
      pl&.add_track!(track, user: user)
    end

    render json: { ok: true, track_id: track.id, title: track.title }
  rescue StandardError => e
    render json: { ok: false, error: e.message }, status: :internal_server_error
  end

  private

  def find_publish_user
    if params[:user_id].present?
      User.find_by(id: params[:user_id])
    elsif params[:user_email].present?
      User.find_by(email_address: params[:user_email].to_s.downcase.strip)
    end
  end
end
