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
  scope :search, ->(q) {
    term = q.to_s.strip
    return none if term.empty?

    ids = connection.select_values(
      sanitize_sql_array(["SELECT rowid FROM resources_fts WHERE resources_fts MATCH ?", term])
    )
    ids.any? ? where(id: ids) : none
  }
end
