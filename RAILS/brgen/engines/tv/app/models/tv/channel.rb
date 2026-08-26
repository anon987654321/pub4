# frozen_string_literal: true

class Tv::Channel < ApplicationRecord
  include CityTenantable

  # Engine-ized Shared via pub4-shared
  include Shared::Notifiable
  tracks_activity created: "TvChannelCreated", updated: "TvChannelUpdated", source_vertical: "tv", actor: :user
  include Shared::MediaProcessable
  include Shared::Reactable

  belongs_to :user
  has_many :videos,        class_name: "Tv::Video",        foreign_key: :tv_channel_id, dependent: :destroy
  has_many :shows,         class_name: "Tv::Show",         foreign_key: :channel_id, dependent: :destroy
  has_many :broadcasts,    class_name: "Tv::Broadcast",    foreign_key: :tv_channel_id, dependent: :destroy
  has_many :subscriptions, class_name: "Tv::Subscription", foreign_key: :tv_channel_id, dependent: :destroy
  has_many :subscribers,   through: :subscriptions, source: :user
  has_one_attached :banner
  has_one_attached :avatar
  process_media_variants :avatar, variants: {
    thumb: { resize_to_limit: [ 240, 240 ], format: :webp }
  }
  process_media_variants :banner, variants: {
    hero: { resize_to_limit: [ 1_600, 600 ], format: :webp },
    card: { resize_to_limit: [ 800, 300 ], format: :webp }
  }

  validates :name, :slug, presence: true
  validates :slug, uniqueness: true, format: { with: /\A[a-z0-9_-]+\z/ }
  before_validation { self.slug ||= name.to_s.parameterize }

  scope :popular, -> { order(subscribers_count: :desc) }

  def to_param = slug
  def live? = broadcasts.where(status: "live").exists?
end
