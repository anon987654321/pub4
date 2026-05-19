# frozen_string_literal: true

class DeclutterChallenge < ApplicationRecord
  belongs_to :user
  belongs_to :item
  belongs_to :outfit, optional: true

  STATUSES = %w[pending completed skipped expired].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :due_on, presence: true

  before_validation :assign_defaults

  scope :active, -> { where(status: "pending").where("due_on >= ?", Date.current) }
  scope :overdue, -> { where(status: "pending").where("due_on < ?", Date.current) }

  def complete!
    transaction do
      update!(status: "completed", completed_at: Time.current)
      item.wear!(outfit:, context: "declutter_challenge")
    end
  end

  def expire!
    update!(status: "expired") if pending? && due_on < Date.current
  end

  def pending? = status == "pending"

  private

  def assign_defaults
    self.user ||= item&.user
    self.status ||= "pending"
    self.due_on ||= 7.days.from_now.to_date
  end
end
