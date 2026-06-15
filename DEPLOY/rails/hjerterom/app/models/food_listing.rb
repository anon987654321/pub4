# frozen_string_literal: true

class FoodListing < ApplicationRecord
  belongs_to :user
  has_many :food_requests, dependent: :destroy

  STATUSES = %w[available reserved taken expired].freeze
  UNITS    = %w[kg portions bags boxes items].freeze

  validates :title, :quantity, :available_until, presence: true
  validates :quantity, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }
  validates :unit, inclusion: { in: UNITS }

  attribute :status, :string, default: "available"

  geocoded_by :pickup_address
  after_validation :geocode, if: :pickup_address_changed?

  scope :available, -> { where(status: "available").where("available_until > ?", Time.current) }
  scope :nearby, ->(lat, lng, km = 20) {
    where("((latitude - ?) * (latitude - ?) + (longitude - ?) * (longitude - ?)) < ?",
      lat, lat, lng, lng, (km / 111.0)**2)
  }
  scope :search, ->(q) {
    term = q.to_s.strip
    return none if term.empty?

    ids = connection.select_values(
      sanitize_sql_array(["SELECT rowid FROM food_listings_fts WHERE food_listings_fts MATCH ?", term])
    )
    ids.any? ? where(id: ids) : none
  }
  scope :ranked_by_distance, ->(lat, lng) {
    return order(created_at: :desc) if lat.blank? || lng.blank?

    lat = lat.to_f
    lng = lng.to_f
    order(
      Arel.sql(sanitize_sql_array([
        "CASE WHEN latitude IS NOT NULL AND longitude IS NOT NULL THEN " \
        "((latitude - ?) * (latitude - ?) + (longitude - ?) * (longitude - ?)) " \
        "ELSE 999 END ASC, created_at DESC",
        lat, lat, lng, lng
      ]))
    )
  }

  before_save :expire_if_past_date

  private

  def expire_if_past_date
    self.status = "expired" if available_until < Time.current && status == "available"
  end
end
