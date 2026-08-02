# frozen_string_literal: true

module Tv
  class LiveStream < ApplicationRecord
    # Engine-ized Shared (tranche10)
    tracks_activity created: "LiveStreamScheduled", updated: "LiveStreamUpdated", source_vertical: "tv", actor: :user
    include Shared::Notifiable

    self.table_name = "tv_live_streams"

    STATUSES = %w[scheduled live ended cancelled].freeze

    belongs_to :user
    belongs_to :channel, class_name: "Tv::Channel", optional: true
    has_many :stream_chats, class_name: "Tv::StreamChat", dependent: :destroy

    validates :title, presence: true
    validates :status, inclusion: { in: STATUSES }, allow_blank: true
    validates :stream_key, presence: true, uniqueness: true, allow_blank: true

    before_validation :default_status

    scope :live, -> { where(status: "live") }
    scope :scheduled, -> { where(status: "scheduled") }
    scope :recent, -> { order(updated_at: :desc) }

    def go_live!
      update!(status: "live", started_at: Time.current)
      record_activity!("LiveStreamStarted", actor: strict_safe(:user), source_vertical: "tv")
    end

    def end_live!
      update!(status: "ended", ended_at: Time.current)
      record_activity!("LiveStreamEnded", actor: strict_safe(:user), source_vertical: "tv")
    end

    private

    def default_status
      self.status = "scheduled" if status.blank?
    end
  end
end
