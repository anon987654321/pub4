# frozen_string_literal: true

class ModerationReport < ApplicationRecord
  belongs_to :user
  belongs_to :reportable, polymorphic: true

  REASONS = %w[spam scam abuse unsafe illegal copyright duplicate other].freeze
STATUSES = %w[open reviewing resolved dismissed].freeze
# What the report picker offers; a caller's own default joins them.
PICKER_REASONS = %w[spam abuse illegal other].freeze
DETAILS_LIMIT = 1_000

def self.picker_reasons(chosen) = (PICKER_REASONS + [ chosen ]).uniq & REASONS

  validates :reason, inclusion: { in: REASONS }
  validates :status, inclusion: { in: STATUSES }

  scope :open, -> { where(status: "open") }
  scope :recent, -> { order(created_at: :desc) }
end
