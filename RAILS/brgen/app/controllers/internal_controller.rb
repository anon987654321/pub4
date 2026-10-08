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
      master_client: Contracts::MasterClient.configured?
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

    playlist = resolve_publish_playlist(user)
    return render(json: { ok: false, error: "playlist not writable" }, status: :forbidden) if params[:playlist_id].present? && playlist.nil?

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

    playlist&.add_track!(track, user: user)

    render json: { ok: true, track_id: track.id, title: track.title }
  rescue StandardError => e
    Rails.logger.error("internal dilla publish failed: #{e.class}: #{e.message}")
    render json: { ok: false, error: "internal publish failed" }, status: :internal_server_error
  end

  private

  def resolve_publish_playlist(user)
    return unless params[:playlist_id].present?

    playlist = Playlist::Playlist.find_by(id: params[:playlist_id])
    playlist if playlist && playlist_writable_by?(playlist, user)
  end

  def playlist_writable_by?(playlist, user)
    return true if playlist.user_id == user.id

    playlist.collaborations.where(user_id: user.id, role: "editor").exists?
  end

  def find_publish_user
    user =
      if params[:user_id].present?
        User.find_by(id: params[:user_id])
      elsif params[:user_email].present?
        User.find_by(email_address: params[:user_email].to_s.downcase.strip)
      end

    user if user && user.deleted_at.nil? && user.deletion_scheduled_at.nil?
  end
end
