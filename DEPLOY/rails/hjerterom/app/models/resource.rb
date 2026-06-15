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
  include Shared::GeoLocatable
  # nearby (bbox standardized) + haversine from concern (old euclid dupe removed)
  scope :by_type,    ->(t) { where(resource_type: t) }
end
