# frozen_string_literal: true

module Tv
  class VideoNote < ApplicationRecord
    self.table_name = "tv_video_notes"

    tracks_activity created: "TvVideoNoteCreated", source_vertical: "tv", actor: :user

    belongs_to :video, class_name: "Tv::Video"
    belongs_to :user

    validates :body, presence: true, length: { maximum: 2_000 }
    validates :timestamp, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

    scope :chronological, -> { order(:timestamp, :created_at) }
    scope :recent, -> { order(created_at: :desc) }

    # See Tv::StreamChat for why both keywords are required. videos/show.html.erb
    # also had the #video_notes_<id> container but no turbo_stream_from, so this
    # stream had no subscriber either; that is now declared next to the container.
    after_create_commit do
      broadcast_append_to "tv:video:#{video_id}:notes",
                                target: "video_notes_#{video_id}",
                                partial: "tv/video_notes/video_note",
                                locals: { video_note: self }
    end
  end
end
