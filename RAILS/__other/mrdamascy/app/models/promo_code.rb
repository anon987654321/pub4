# frozen_string_literal: true

class PromoCode < ApplicationRecord
  KINDS = %w[percent fixed free_delivery].freeze

  normalizes :code, with: ->(code) { code.to_s.strip.upcase }

  validates :code, presence: true, uniqueness: true
  validates :kind, inclusion: { in: KINDS }
  validates :value, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :min_basket_ore, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :active, -> { where(active: true) }
end
