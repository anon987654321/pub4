# frozen_string_literal: true

module Tv
  class VideoNote < ApplicationRecord
    self.table_name = "tv_video_notes"

    include Shared::ActivityTrackable
    tracks_activity created: "TvVideoNoteCreated", source_vertical: "tv", actor: :user

    belongs_to :video, class_name: "Tv::Video"
    belongs_to :user

    validates :body, presence: true, length: { maximum: 2_000 }
    validates :timestamp, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

    scope :chronological, -> { order(:timestamp, :created_at) }
    scope :recent, -> { order(created_at: :desc) }

    after_create_commit do
      broadcast_append_later_to "tv:video:#{video_id}:notes"
    end
  end
end
