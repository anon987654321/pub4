# frozen_string_literal: true

class Takeaway::Order
  # When the food arrives and who brings it: the estimate, the progress fill, the
  # courier's name and distance, and the dispatch that picks the courier.
  module Delivery
    extend ActiveSupport::Concern

    # Minutes from order placement to the end of each stage. Anchored to
    # created_at (not "now") so the estimate visibly shrinks as the order
    # actually advances, instead of a fixed "25-35 min" string that never
    # reflects what's happening to this order.
    ETA_MINUTES_BY_STATUS = {
      "pending" => 35,
      "confirmed" => 30,
      "preparing" => 20,
      "out_for_delivery" => 10,
      "delivered" => 0
    }.freeze

    # How far from the kitchen dispatch will look for a courier. Bergen end to end
    # is about 10 km, so this is "anywhere in the city" rather than a tuned value.
    DISPATCH_RADIUS_KM = 10

    def scheduled? = scheduled_for.present?

    # A scheduled order is not late because it was placed hours ago: its estimate
    # is anchored to when the customer asked for it, not to when they ordered.
    def estimated_ready_at
      return nil if status == "cancelled"
      return scheduled_for if scheduled? && scheduled_for > Time.current

      anchor = scheduled? ? scheduled_for : created_at
      anchor + ETA_MINUTES_BY_STATUS.fetch(status, 30).minutes
    end

    # Fraction of the delivery journey complete, for a real (non-decorative)
    # progress fill under the status timeline. nil once terminal — there's
    # nothing left to fill toward.
    def progress_fraction
      return nil if TERMINAL_STATUSES.include?(status)
      stages = STATUSES - TERMINAL_STATUSES
      (stages.index(status).to_i + 1) / stages.size.to_f
    end

    # The courier's name for customer-facing copy, or nil when nobody is assigned.
    # strict_safe because an order loaded by id has no association preloaded.
    def courier_display_name
      strict_safe(:delivery_driver)&.display_name
    end

    # Kitchen to customer, as the courier actually has to travel it. nil unless
    # both ends have coordinates — the order page falls back to the status ETA.
    def courier_distance_km
      driver = strict_safe(:delivery_driver)
      return nil unless driver&.location?

      restaurant_record = strict_safe(:restaurant)
      return nil unless restaurant_record&.latitude && restaurant_record&.longitude

      Takeaway::DeliveryDriver.haversine(
        driver.current_lat, driver.current_lng,
        restaurant_record.latitude, restaurant_record.longitude
      )
    end

    private

    # Nearest free courier to the kitchen, or nil. Deliberately not a validation
    # or a callback: an order with nobody to carry it is a real operational state
    # (nobody on shift at 3am), and refusing the transition would strand it in
    # `preparing` forever rather than surfacing the problem.
    def dispatch_driver_id
      restaurant_record = strict_safe(:restaurant)
      return nil unless restaurant_record&.latitude && restaurant_record&.longitude

      Takeaway::DeliveryDriver.nearest_free(
        restaurant_record.latitude,
        restaurant_record.longitude,
        DISPATCH_RADIUS_KM
      )&.id
    end
  end
end
