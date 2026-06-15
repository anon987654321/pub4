# frozen_string_literal: true

class Partner < ApplicationRecord
  has_many :transfers, dependent: :destroy

  KINDS = %w[food_bank retailer donor_hub community_center].freeze

  validates :name, presence: true
  validates :kind, inclusion: { in: KINDS }

  scope :active, -> { where(active: true) }

  geocoded_by :address
  after_validation :geocode, if: :address_changed?
end