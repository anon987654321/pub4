# frozen_string_literal: true

module Tv
  class StreamChat < ApplicationRecord
    self.table_name = "tv_stream_chats"

    tracks_activity created: "TvStreamChatCreated", source_vertical: "tv", visibility: "private", actor: :user

    belongs_to :live_stream, class_name: "Tv::LiveStream"
    belongs_to :user

    validates :message, presence: true, length: { maximum: 1_000 }

    scope :chronological, -> { order(:created_at) }

    after_create_commit do
      broadcast_append_later_to "tv:live_stream:#{live_stream_id}:entries"
    end
  end
end
