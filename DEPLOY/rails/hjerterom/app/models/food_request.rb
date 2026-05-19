# frozen_string_literal: true

class FoodRequest < ApplicationRecord
  belongs_to :food_listing
  belongs_to :user

  STATUSES = %w[pending accepted declined picked_up cancelled].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :message, length: { maximum: 1000 }, allow_blank: true

  attribute :status, :string, default: "pending"

  after_create_commit -> { broadcast_prepend_to [food_listing, "requests"] }

  scope :pending,  -> { where(status: "pending") }
  scope :accepted, -> { where(status: "accepted") }
end
