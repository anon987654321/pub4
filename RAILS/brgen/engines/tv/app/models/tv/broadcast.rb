# frozen_string_literal: true

class Tv::Broadcast < ApplicationRecord
  include Shared::MediaProcessable
  include Tv::ChannelTenanted
  tracks_activity created: "BroadcastScheduled", updated: "BroadcastUpdated", source_vertical: "tv", actor: :user

  belongs_to :channel, class_name: "Tv::Channel", foreign_key: :tv_channel_id, inverse_of: :broadcasts
  belongs_to :user
  has_one_attached :thumbnail
  process_media_variants :thumbnail, variants: {
    poster: { resize_to_limit: [ 1_280, 720 ], format: :webp },
    thumb: { resize_to_limit: [ 480, 270 ], format: :webp }
  }

  validates :title, presence: true
  before_create { self.stream_key = SecureRandom.hex(16) }

  # Same nil-channel exposure as Tv::Video — tv/home/index renders
  # b.channel.name for every @live row. It has not fired only because no
  # broadcast is live; the crash was one row away, not absent.
  scope :live,      -> { where(status: "live").in_current_city }
  scope :scheduled, -> { where(status: "scheduled").in_current_city }

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
