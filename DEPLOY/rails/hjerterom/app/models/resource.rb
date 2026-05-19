# frozen_string_literal: true

class Resource < ApplicationRecord
  belongs_to :user
  belongs_to :category

  RESOURCE_TYPES = %w[crisis_line support_group therapist hotline community_center other].freeze

  validates :title, presence: true
  validates :resource_type, inclusion: { in: RESOURCE_TYPES }

  geocoded_by :address
  after_validation :geocode, if: :address_changed?

  scope :verified,   -> { where(verified: true) }
  scope :nearby,     ->(lat, lng, km = 50) {
    where("((latitude - ?) * (latitude - ?) + (longitude - ?) * (longitude - ?)) < ?",
      lat, lat, lng, lng, (km / 111.0)**2)
  }
  scope :by_type,    ->(t) { where(resource_type: t) }
end
