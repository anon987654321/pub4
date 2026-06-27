# frozen_string_literal: true

class ComicStrip < ApplicationRecord
  include Shared::Reactable

  belongs_to :user

  validates :prompt, presence: true
  validates :style, presence: true
  validates :status, presence: true

  STATUSES = %w[pending processing completed failed].freeze

  def refresh_status!
    return if status.in?(%w[completed failed])
    return if prediction_id.blank?

    result = ReplicateService.new.get_prediction(prediction_id)
    case result["status"]
    when "succeeded"
      update!(status: "completed", image_urls: result["output"])
    when "failed"
      update!(status: "failed")
    when "processing", "starting"
      update!(status: "processing")
    end
  end
end