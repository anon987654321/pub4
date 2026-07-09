# frozen_string_literal: true

module Playlist
  class TimestampedComment < ApplicationRecord
    self.table_name = "playlist_timestamped_comments"

    belongs_to :track, class_name: "Playlist::Track"
    belongs_to :user

    validates :body, presence: true, length: { maximum: 2_000 }
    validates :timestamp_seconds, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

    scope :chronological, -> { order(:timestamp_seconds, :created_at) }

    after_create_commit do
      broadcast_append_later_to "playlist:track:#{track_id}:comments"
    end
  end
end
