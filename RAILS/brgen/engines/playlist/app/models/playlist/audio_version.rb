# frozen_string_literal: true

module Playlist
  class AudioVersion < ApplicationRecord
    self.table_name = "playlist_audio_versions"

    belongs_to :track, class_name: "Playlist::Track"
    belongs_to :user, optional: true

    validates :original_filename, length: { maximum: 255 }, allow_blank: true
    validates :byte_size, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

    scope :recent, -> { order(created_at: :desc) }
  end
end
