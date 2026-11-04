# frozen_string_literal: true

module Tv
  class StreamChat < ApplicationRecord
    self.table_name = "tv_stream_chats"

    tracks_activity created: "TvStreamChatCreated", source_vertical: "tv", visibility: "private", actor: :user

    include Shared::StrictSafeAssociations

    belongs_to :live_stream, class_name: "Tv::LiveStream"
    belongs_to :user

    # One line per viewer per stream in this window, on top of the global write
    # throttle, so one person cannot flood every viewer's broadcast.
    SLOW_MODE = 2.seconds

    validates :message, presence: true, length: { maximum: 1_000 }
    validate :outside_slow_mode, on: :create

    scope :chronological, -> { order(:created_at) }

    scope :page_log, -> { includes(:user).chronological.limit(200) }

    # The line's author, read without a lazy load: the broadcast renders this
    # off a record nothing preloaded.
    def author = strict_safe(:user)

    private

    def outside_slow_mode
      recent = self.class.where(user_id:, live_stream_id:, created_at: SLOW_MODE.ago..)
      errors.add(:base, I18n.t("tv.stream_chat_slow_mode")) if recent.exists?
    end

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
