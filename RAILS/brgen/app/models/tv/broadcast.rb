# frozen_string_literal: true

class Tv::Broadcast < ApplicationRecord
  include Shared::MediaProcessable
  tracks_activity created: "BroadcastScheduled", updated: "BroadcastUpdated", source_vertical: "tv", actor: :user

  belongs_to :channel, class_name: "Tv::Channel", foreign_key: :tv_channel_id
  belongs_to :user
  has_one_attached :thumbnail
  process_media_variants :thumbnail, variants: {
    poster: { resize_to_limit: [ 1_280, 720 ], format: :webp },
    thumb: { resize_to_limit: [ 480, 270 ], format: :webp },
  }

  validates :title, presence: true
  before_create { self.stream_key = SecureRandom.hex(16) }

  scope :live,      -> { where(status: "live") }
  scope :scheduled, -> { where(status: "scheduled") }

  # `actor: user` is a lazy belongs_to read, and a broadcast toggled from a
  # controller is loaded by id with nothing preloaded — so under strict loading
  # (on in every environment, raising outside development) this raised after
  # update! had already flipped the status. See Shared::StrictSafeAssociations.
  def go_live!
    update!(status: "live", started_at: Time.current)
    record_activity!("BroadcastStarted", actor: strict_safe(:user), source_vertical: "tv")
  end

  def end_live!
    update!(status: "ended", ended_at: Time.current)
    record_activity!("BroadcastEnded", actor: strict_safe(:user), source_vertical: "tv")
  end
end
