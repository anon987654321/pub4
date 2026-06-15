# frozen_string_literal: true

class Tv::Channel < ApplicationRecord
  belongs_to :user
  has_many :videos,        class_name: "Tv::Video",        foreign_key: :tv_channel_id, dependent: :destroy
  has_many :broadcasts,    class_name: "Tv::Broadcast",    foreign_key: :tv_channel_id, dependent: :destroy
  has_many :subscriptions, class_name: "Tv::Subscription", foreign_key: :tv_channel_id, dependent: :destroy
  has_many :subscribers,   through: :subscriptions, source: :user
  has_one_attached :banner
  has_one_attached :avatar

  validates :name, :slug, presence: true
  validates :slug, uniqueness: true, format: { with: /\A[a-z0-9_-]+\z/ }
  before_validation { self.slug ||= name.to_s.parameterize }

  scope :popular, -> { order(subscribers_count: :desc) }
  scope :search, ->(q) {
    term = q.to_s.strip
    return none if term.empty?

    ids = connection.select_values(
      sanitize_sql_array(["SELECT rowid FROM tv_channels_fts WHERE tv_channels_fts MATCH ?", term])
    )
    ids.any? ? where(id: ids) : none
  }

  def to_param = slug
  def live?    = broadcasts.where(status: "live").exists?
end
