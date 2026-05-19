# frozen_string_literal: true

class Tv::Broadcast < ApplicationRecord
  belongs_to :channel, class_name: "Tv::Channel", foreign_key: :tv_channel_id
  belongs_to :user
  has_one_attached :thumbnail

  validates :title, presence: true
  before_create { self.stream_key = SecureRandom.hex(16) }

  scope :live,      -> { where(status: "live") }
  scope :scheduled, -> { where(status: "scheduled") }

  def go_live!  = update!(status: "live",  started_at: Time.current)
  def end_live! = update!(status: "ended", ended_at: Time.current)
end
