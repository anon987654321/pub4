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

    # The nearest available courier who is not already carrying an order.
    #
    # `nearby` above is a bounding box, so its "nearest" is really "somewhere in
    # the square" — a driver at the corner is 1.41x further than one on the edge.
    # Order the survivors by real haversine distance rather than trusting the
    # box. The candidate set is small (available drivers within km), so this
    # costs one short array sort, not a table scan.
    def self.nearest_free(lat, lng, km = 10)
      return nil if lat.blank? || lng.blank?

      busy = Takeaway::Order.where(status: "out_for_delivery")
                            .where.not(delivery_driver_id: nil)
                            .select(:delivery_driver_id)
      available.nearby(lat, lng, km)
               .where.not(id: busy)
               .to_a
               .min_by { |driver| haversine(lat, lng, driver.current_lat, driver.current_lng) }
    end

    # Courier name for customer-facing copy. strict_safe is private, so this has
    # to live here rather than being reached for from Takeaway::Order.
    def display_name
      strict_safe(:user)&.display_name
    end

    def location?
      current_lat.present? && current_lng.present?
    end

    # Whether this courier is carrying an order right now. `orders` resolves
    # through delivery_driver_id, which nothing wrote until dispatch existed.
    def on_delivery?
      orders.where(status: "out_for_delivery").exists?
    end

    def geo? = location?
    def latitude = current_lat
    def longitude = current_lng
  end
end
