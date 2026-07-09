# frozen_string_literal: true

class ImportRun < ApplicationRecord
  belongs_to :platform

  STATUSES = %w[running succeeded failed].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :started_at, presence: true

  scope :recent, -> { order(started_at: :desc) }

  def mark_succeeded!(ports_count:, source_revision: nil)
    update!(
      status: "succeeded",
      finished_at: Time.current,
      ports_count: ports_count,
      source_revision: source_revision
    )
  end

  def mark_failed!(error_message)
    update!(status: "failed", finished_at: Time.current, error_message: error_message)
  end
end