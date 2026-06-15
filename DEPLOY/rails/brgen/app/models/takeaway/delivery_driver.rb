# frozen_string_literal: true

module Takeaway
  class DeliveryDriver < ApplicationRecord
    self.table_name = "takeaway_delivery_drivers"

    VEHICLE_TYPES = %w[bicycle scooter car van walking].freeze

    belongs_to :user
    has_many :orders, class_name: "Takeaway::Order", dependent: :nullify

    validates :vehicle_type, inclusion: { in: VEHICLE_TYPES }, allow_blank: true
    validates :license_number, length: { maximum: 128 }, allow_blank: true

    scope :available, -> { where(available: true) }
    include Shared::GeoLocatable
    # custom lat/lng columns (current_*); keep specialized bbox + expose haversine via concern
    scope :nearby, ->(lat, lng, km = 10) {
      return all if lat.blank? || lng.blank?
      where(current_lat: (lat.to_f - km.to_f / 111)..(lat.to_f + km.to_f / 111))
        .where(current_lng: (lng.to_f - km.to_f / 111)..(lng.to_f + km.to_f / 111))
    }

    def location?
      current_lat.present? && current_lng.present?
    end

    def geo? = location?
    def latitude = current_lat
    def longitude = current_lng
  end
end
