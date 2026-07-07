# frozen_string_literal: true

class Recommendation < ApplicationRecord
  belongs_to :user
  belongs_to :item, optional: true
  belongs_to :outfit, optional: true

  validates :kind, :reason, presence: true
  validates :score, numericality: true, allow_nil: true

  enum :kind, {
    outfit: "outfit",
    declutter: "declutter",
    purchase_gap: "purchase_gap",
    repair: "repair",
    resale: "resale",
    packing: "packing"
  }

  scope :active, -> { where(dismissed_at: nil) }
  scope :recent, -> { order(created_at: :desc) }
end
