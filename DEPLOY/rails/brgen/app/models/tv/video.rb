# frozen_string_literal: true

class Tv::Video < ApplicationRecord
  belongs_to :channel,     class_name: "Tv::Channel",   foreign_key: :tv_channel_id
  belongs_to :user
  has_many :view_events,   class_name: "Tv::ViewEvent", foreign_key: :tv_video_id, dependent: :destroy
  has_one_attached :video_file
  has_one_attached :thumbnail

  STATUSES = %w[processing ready published unlisted].freeze
  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES }, allow_nil: true

  scope :published, -> { where(status: "published").order(published_at: :desc) }
  scope :trending,  -> { published.order(views_count: :desc) }
  scope :recent,    -> { published.order(published_at: :desc) }

  def duration_formatted
    return "—" unless duration_seconds
    h, rem = duration_seconds.divmod(3600)
    m, s   = rem.divmod(60)
    h > 0 ? "%d:%02d:%02d" % [h, m, s] : "%d:%02d" % [m, s]
  end
end
