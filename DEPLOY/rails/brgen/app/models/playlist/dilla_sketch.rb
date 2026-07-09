# frozen_string_literal: true

class Playlist::DillaSketch < ApplicationRecord
  self.table_name = "playlist_dilla_sketches"

  tracks_activity created: "DillaSketchCreated", updated: "DillaSketchUpdated", source_vertical: "playlist", visibility: "private", actor: :user

  belongs_to :user
  belongs_to :playlist, class_name: "Playlist::Playlist", optional: true
  belongs_to :set, class_name: "Playlist::Set", optional: true

  MAX_NAME = 100
  validates :name, presence: true, length: { maximum: MAX_NAME }
  validates :state, presence: true

  scope :recent, -> { order(created_at: :desc) }

  def to_lab_hash
    # Compatible with dilla.html #hash encode (pat_, aud_, mix_ expected at top)
    # state is stored as {pat_, aud_, mix_} or {pat: , ...} — normalize
    s = state.deep_symbolize_keys
    pat = s.fetch(:pat_, nil) || s.fetch(:pat, nil)
    aud = s.fetch(:aud_, nil) || s.fetch(:aud, nil)
    mix = s.fetch(:mix_, nil) || s.fetch(:mix, nil)
    if pat || aud || mix
      { pat_: pat, aud_: aud, mix_: mix }
    else
      s
    end
  end

  def lab_url(base = "/dilla/dilla.html")
    hash = encode_lab_state
    return base if hash.blank?
    "#{base}##{hash}"
  end

  def encode_lab_state
    JSON.dump(to_lab_hash).then { |s| Base64.strict_encode64(s) }
  rescue StandardError => e
    # Swallow for user-facing share; errors are non-fatal for encode
    ""
  end
end
