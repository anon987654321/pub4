# frozen_string_literal: true

class FoodItem < ApplicationRecord
  enum :category, { dry_goods: 0, fresh: 1, frozen: 2, hygiene: 3, clothing: 4, books: 5, other: 6 }, default: :other
  enum :quality_state, { usable: 0, urgent: 1, unusable: 2 }, default: :usable

  belongs_to :donation
  belongs_to :box, optional: true

  validates :name, presence: true
  validates :quantity, numericality: { greater_than: 0 }, allow_nil: true

  scope :available, -> { where(box_id: nil).where.not(quality_state: :unusable) }
  scope :urgent, -> { where(quality_state: :urgent) }
end
