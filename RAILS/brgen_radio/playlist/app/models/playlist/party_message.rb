# frozen_string_literal: true

module Playlist
  class PartyMessage < ApplicationRecord
    self.table_name = "playlist_party_messages"

    belongs_to :listening_party, class_name: "Playlist::ListeningParty"
    belongs_to :user

    validates :body, presence: true, length: { maximum: 500 }

    scope :chronological, -> { order(:created_at) }

    after_create_commit do
      broadcast_append_to listening_party.stream_name,
        target: "party_messages",
        partial: "playlist/party_messages/message",
        locals: { message: self }
    end
  end
end
