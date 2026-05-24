# frozen_string_literal: true

class WardrobeItem < ApplicationRecord
  CONDITIONS = %w[new excellent good worn repair retire].freeze

  belongs_to :user
  belongs_to :item

  validates :condition, inclusion: { in: CONDITIONS }, allow_blank: true
  validates :user_id, uniqueness: { scope: :item_id }

  scope :recent, -> { order(created_at: :desc) }
  scope :needs_attention, -> { where(condition: %w[repair retire]) }

  def age_in_days
    return 0 unless acquisition_date

    (Date.current - acquisition_date).to_i
  end
end
