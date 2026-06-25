# frozen_string_literal: true

class Tv::Channel < ApplicationRecord
  include CityTenantable

  # Engine-ized Shared via pub4-shared
  include Shared.concern(:Notifiable) rescue nil
  include Shared.concern(:ActivityTrackable) rescue nil
  include Shared.concern(:Reactable) rescue nil

  belongs_to :user
  has_many :videos,        class_name: "Tv::Video",        foreign_key: :tv_channel_id, dependent: :destroy
  has_many :shows,         class_name: "Tv::Show",         foreign_key: :channel_id, dependent: :destroy
  has_many :broadcasts,    class_name: "Tv::Broadcast",    foreign_key: :tv_channel_id, dependent: :destroy
  has_many :subscriptions, class_name: "Tv::Subscription", foreign_key: :tv_channel_id, dependent: :destroy
  has_many :subscribers,   through: :subscriptions, source: :user
  has_one_attached :banner
  has_one_attached :avatar

  validates :name, :slug, presence: true
  validates :slug, uniqueness: true, format: { with: /\A[a-z0-9_-]+\z/ }
  before_validation { self.slug ||= name.to_s.parameterize }

  scope :popular, -> { order(subscribers_count: :desc) }

  def to_param = slug
  def live?    = broadcasts.where(status: "live").exists?
end
