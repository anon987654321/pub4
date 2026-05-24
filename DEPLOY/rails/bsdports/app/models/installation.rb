# frozen_string_literal: true

class Installation < ApplicationRecord
  STATUSES = %w[pending installed outdated removed failed].freeze

  belongs_to :user
  belongs_to :port

  validates :status, inclusion: { in: STATUSES }, allow_blank: true
  validates :version, length: { maximum: 128 }, allow_blank: true

  before_validation :default_status

  scope :active, -> { where(status: %w[pending installed outdated]) }
  scope :recent, -> { order(updated_at: :desc) }

  private

  def default_status
    self.status = "pending" if status.blank?
  end
end
