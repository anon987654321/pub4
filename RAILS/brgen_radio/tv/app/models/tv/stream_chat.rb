# frozen_string_literal: true

module Tv
  class StreamChat < ApplicationRecord
    self.table_name = "tv_stream_chats"

    tracks_activity created: "TvStreamChatCreated", source_vertical: "tv", visibility: "private", actor: :user

    belongs_to :live_stream, class_name: "Tv::LiveStream"
    belongs_to :user

    validates :message, presence: true, length: { maximum: 1_000 }

    scope :chronological, -> { order(:created_at) }

    # Both keywords are load-bearing and both were missing. Without partial: the
    # broadcast resolved to tv/stream_chats/_stream_chat, which did not exist, and
    # the enqueued job raised MissingTemplate; without target: it would have
    # appended to a "tv_stream_chats" element the page does not have. The result was
    # that only the submitter — served by create.turbo_stream.erb — ever saw a new
    # line, and everyone else watching the stream saw nothing.
    after_create_commit do
      broadcast_append_to "tv:live_stream:#{live_stream_id}:entries",
                                target: "tv-live-stream-#{live_stream_id}-entries",
                                partial: "tv/stream_chats/stream_chat",
                                locals: { stream_chat: self }
    end
  end
end
