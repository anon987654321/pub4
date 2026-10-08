# frozen_string_literal: true

module Playlist
  class ListeningParty < ApplicationRecord
    self.table_name = "playlist_listening_parties"

    STATUSES = %w[active ended].freeze

    tracks_activity created: "PlaylistListeningPartyStarted", source_vertical: "playlist", actor: :host

    belongs_to :set, class_name: "Playlist::Set", foreign_key: :playlist_set_id, inverse_of: :listening_party
    belongs_to :host, class_name: "User"
    belongs_to :current_track, class_name: "Playlist::Track", optional: true
    has_many :party_messages, class_name: "Playlist::PartyMessage", foreign_key: :listening_party_id,
             dependent: :destroy, inverse_of: :listening_party

    validates :status, inclusion: { in: STATUSES }
    validates :join_code, presence: true, uniqueness: true
    validates :position_seconds, numericality: { greater_than_or_equal_to: 0 }

    scope :active, -> { where(status: "active") }

    before_validation :ensure_join_code, on: :create

    def active? = status == "active"

    def end!
      update!(status: "ended", current_track: nil, position_seconds: 0)
    end

    def sync!(track:, position_seconds:)
      update!(current_track: track, position_seconds: position_seconds.to_i)
      broadcast_replace_to stream_name,
        target: "listening_party_sync",
        partial: "playlist/listening_parties/sync",
        locals: { party: self, track: track }
    end

    def stream_name = "playlist:listening_party:#{id}"

    private

    def ensure_join_code
      self.join_code ||= SecureRandom.alphanumeric(8).upcase
    end
  end
end
