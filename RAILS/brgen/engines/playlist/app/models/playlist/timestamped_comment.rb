# frozen_string_literal: true

module Playlist
  class TimestampedComment < ApplicationRecord
    self.table_name = "playlist_timestamped_comments"

    belongs_to :track, class_name: "Playlist::Track"
    belongs_to :user

    validates :body, presence: true, length: { maximum: 2_000 }
    validates :timestamp_seconds, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

    scope :chronological, -> { order(:timestamp_seconds, :created_at) }

    # There was an after_create_commit here broadcasting to
    # "playlist:track:<id>:comments" with no partial, no target, and no
    # turbo_stream_from anywhere in the tree. Every comment enqueued a Solid Queue
    # job that raised MissingTemplate into a stream with no subscriber — on a
    # 1-vCPU box, per comment.
    #
    # It is removed rather than wired because a DOM append could not have worked
    # here anyway: hosted_tracks/show.html.erb hands the comments to the player as
    # JSON (`comments: @comments.map { ... }`), so the live surface is the player's
    # own state, not an element. Making these live means feeding that JSON, which is
    # a product decision about the player, not a missing partial.
  end
end
