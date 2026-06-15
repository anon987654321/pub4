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
  include Shared::GeoLocatable
  scope :search, ->(q) {
    ids = connection.select_values(sanitize_sql_array(["SELECT rowid FROM food_listings_fts WHERE food_listings_fts MATCH ?", q]))
    ids.any? ? where(id: ids) : none
  }

  before_save :expire_if_past_date

  private

  def expire_if_past_date
    self.status = "expired" if available_until < Time.current && status == "available"
  end
end