# frozen_string_literal: true

class RoutePlanner
  def self.build_for(date: Date.current)
    new(date:).build
  end

  def initialize(date:)
    @date = date
  end

  def build
    route = DeliveryRoute.find_or_initialize_by(route_date: date)
    return route if route.persisted? && route.delivery_stops.any?

    route.status = :planned
    route.save! unless route.persisted?

    stops = candidate_stops
    ordered = nearest_neighbor(stops)
    route.delivery_stops.destroy_all
    ordered.each_with_index do |stop, index|
      route.delivery_stops.create!(stop.merge(sequence: index))
    end
    route
  end

  private

  attr_reader :date

  def candidate_stops
    Donation.needs_action.filter_map do |donation|
      donor = donation.donor
      next unless donor&.latitude && donor&.longitude

      {
        stop_kind: :pickup,
        label: "Pickup #{donation.source_name}",
        latitude: donor.latitude,
        longitude: donor.longitude,
        reference: donation
      }
    end + Beneficiary.where(active: true).filter_map do |beneficiary|
      next unless beneficiary.latitude && beneficiary.longitude

      {
        stop_kind: :dropoff,
        label: "Dropoff #{beneficiary.name}",
        latitude: beneficiary.latitude,
        longitude: beneficiary.longitude,
        reference: beneficiary
      }
    end
  end

  def nearest_neighbor(stops)
    return [] if stops.empty?

    remaining = stops.dup
    ordered = [remaining.shift]
    while remaining.any?
      current = ordered.last
      next_stop = remaining.min_by { |stop| distance(current, stop) }
      remaining.delete(next_stop)
      ordered << next_stop
    end
    ordered
  end

  def distance(a, b)
    Math.hypot(a[:latitude].to_f - b[:latitude].to_f, a[:longitude].to_f - b[:longitude].to_f)
  end
end