# frozen_string_literal: true

class Playlist::DillaSketch < ApplicationRecord
  self.table_name = "playlist_dilla_sketches"

  belongs_to :user
  belongs_to :playlist, class_name: "Playlist::Playlist", optional: true
  belongs_to :set, class_name: "Playlist::Set", optional: true

  validates :name, presence: true, length: { maximum: 100 }
  validates :state, presence: true

  scope :recent, -> { order(created_at: :desc) }

  def to_lab_hash
    # Compatible with dilla.html #hash encode (pat_, aud_, mix_ expected at top)
    # state is stored as {pat_, aud_, mix_} or {pat: , ...} — normalize
    s = state.deep_symbolize_keys
    if s[:pat_]
      { pat_: s[:pat_], aud_: s[:aud_], mix_: s[:mix_] }
    elsif s[:pat]
      { pat_: s[:pat], aud_: s[:aud], mix_: s[:mix] }
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
    begin
      btoa = Base64.strict_encode64(JSON.dump(to_lab_hash))
      btoa
    rescue
      ""
    end
  end

  private

  def btoa(str)
    # In case we call from ruby context for tests
    Base64.strict_encode64(str)
  end
end
