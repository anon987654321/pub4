# frozen_string_literal: true

class SupportRequest < ApplicationRecord
  belongs_to :user

  STATUSES   = %w[open in_progress resolved closed].freeze
  PRIORITIES = %w[low normal high urgent].freeze

  validates :subject, presence: true, length: { maximum: 200 }
  validates :status, inclusion: { in: STATUSES }
  validates :priority, inclusion: { in: PRIORITIES }

  attribute :status,   :string, default: "open"
  attribute :priority, :string, default: "normal"

  scope :open,    -> { where(status: %w[open in_progress]) }
  scope :urgent,  -> { where(priority: "urgent") }
end
