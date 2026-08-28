# frozen_string_literal: true

class Playlist::DillaSketch < ApplicationRecord
  self.table_name = "playlist_dilla_sketches"

  tracks_activity created: "DillaSketchCreated", updated: "DillaSketchUpdated", source_vertical: "playlist", visibility: "private", actor: :user

  belongs_to :user
  belongs_to :playlist, class_name: "Playlist::Playlist", optional: true
  belongs_to :set, class_name: "Playlist::Set", optional: true
  belongs_to :track, class_name: "Playlist::Track", optional: true

  has_one_attached :render

  MAX_NAME = 100
  STATUSES = %w[idle queued rendering ready failed].freeze

  validates :name, presence: true, length: { maximum: MAX_NAME }
  validates :state, presence: true
  validates :render_status, inclusion: { in: STATUSES }, allow_nil: true

  scope :recent, -> { order(created_at: :desc) }

  def to_lab_hash
    s = state.is_a?(Hash) ? state.deep_symbolize_keys : {}
    pat = s.fetch(:pat_, nil) || s.fetch(:pat, nil)
    aud = s.fetch(:aud_, nil) || s.fetch(:aud, nil)
    mix = s.fetch(:mix_, nil) || s.fetch(:mix, nil)
    base = if pat || aud || mix
             { pat_: pat, aud_: aud, mix_: mix }
    else
             s
    end
    base.merge(
      style: (style.presence || base.dig(:mix_, :style) || "dilla"),
      bars: (bars.presence || base.dig(:mix_, :bars) || 12),
      name: name
    )
  end

  def lab_url(base = "/dilla/dilla.html")
    hash = encode_lab_state
    q = "sketch_id=#{id}"
    q += "&playlist_id=#{playlist_id}" if playlist_id
    q += "&set_id=#{set_id}" if set_id
    return "#{base}?#{q}" if hash.blank?

    "#{base}?#{q}##{hash}"
  end

  def encode_lab_state
    JSON.dump(to_lab_hash).then { |s| Base64.strict_encode64(s) }
  rescue StandardError
    ""
  end

  def enqueue_render!(publish: true)
    update!(render_status: "queued", render_error: nil)
    DillaRenderJob.perform_later(id, publish: publish)
  end

  def publish_as_track!
    return track if track.present? && track.audio_file.attached?
    return nil unless render.attached?

    t = Playlist::Track.create!(
      user: user,
      title: name.to_s.truncate(100),
      artist: user.try(:display_name).presence || user.try(:email).to_s.split("@").first.presence || "Dilla Lab",
      source_type: "dilla",
      privacy: "unlisted"
    )
    render.blob.open do |file|
      t.audio_file.attach(
        io: file,
        filename: render.filename.to_s,
        content_type: render.content_type.presence || "audio/mpeg"
      )
    end
    if playlist
      playlist.add_track!(t, user: user)
    elsif set&.respond_to?(:tracks)
      # sets may use a different association; best-effort
      set.tracks << t if set.tracks.respond_to?(:<<)
    end
    t
  end
end
