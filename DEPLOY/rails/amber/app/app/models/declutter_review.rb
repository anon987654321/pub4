class DeclutterReview < ApplicationRecord
  belongs_to :user
  belongs_to :item

  REASONS = %w[wear love need guilt expensive gift memory goal_weight past_self aspirational rare status uncomfortable duplicate].freeze
  DECISIONS = %w[keep wear_this_week repair sell donate recycle sentimental_archive declutter_box release].freeze

  validates :reason_kept, inclusion: { in: REASONS }, allow_blank: true
  validates :decision, inclusion: { in: DECISIONS }, allow_blank: true
  validates :notes, length: { maximum: 1_000 }

  before_validation :assign_user

  def guilt_based? = %w[guilt expensive gift goal_weight status].include?(reason_kept)

  private

  def assign_user
    self.user ||= item&.user
  end
end
