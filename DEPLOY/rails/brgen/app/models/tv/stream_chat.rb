# frozen_string_literal: true

module Tv
  class StreamChat < ApplicationRecord
    self.table_name = "tv_stream_chats"

    belongs_to :live_stream, class_name: "Tv::LiveStream"
    belongs_to :user

    belongs_to :moderated_by, class_name: "User", optional: true

    validates :message, presence: true, length: { maximum: 1_000 }
    validates :moderation_status, inclusion: { in: %w[visible hidden] }

    scope :chronological, -> { order(:created_at) }
    scope :visible, -> { where(moderation_status: "visible") }

    after_create_commit do
      broadcast_append_later_to "tv:live_stream:#{live_stream_id}:entries"
    end
  end
end
