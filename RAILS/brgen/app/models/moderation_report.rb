# frozen_string_literal: true

class ModerationReport < ApplicationRecord
  belongs_to :user
  belongs_to :reportable, polymorphic: true

  REASONS = %w[spam scam abuse unsafe illegal duplicate other].freeze
  STATUSES = %w[open reviewing resolved dismissed].freeze

  validates :reason, inclusion: { in: REASONS }
  validates :status, inclusion: { in: STATUSES }

  scope :open, -> { where(status: "open") }
  scope :recent, -> { order(created_at: :desc) }
end
