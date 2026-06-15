# frozen_string_literal: true

require "net/http"
require "json"

class OsrmRouteService
  BASE_URL = ENV.fetch("OSRM_BASE_URL", "https://router.project-osrm.org")

  def self.optimize_stops(stops)
    new(stops).optimize
  end

  def initialize(stops)
    @stops = stops.select { |s| s[:latitude].present? && s[:longitude].present? }
  end

  def optimize
    return { stops: @stops, distance_km: 0, duration_min: 0 } if @stops.size < 2

    coords = @stops.map { |s| "#{s[:longitude]},#{s[:latitude]}" }.join(";")
    uri = URI("#{BASE_URL}/trip/v1/driving/#{coords}?source=first&roundtrip=false")
    data = JSON.parse(Net::HTTP.get(uri))
    waypoints = data["waypoints"] || []
    order = waypoints.map { |w| w["waypoint_index"] }
    ordered = order.map { |i| @stops[i] }.compact

    {
      stops: ordered.presence || @stops,
      distance_km: (data.dig("trips", 0, "distance").to_f / 1000).round(2),
      duration_min: (data.dig("trips", 0, "duration").to_f / 60).round(1)
    }
  rescue StandardError => e
    Rails.logger.warn("OSRM route fallback: #{e.message}")
    { stops: @stops, distance_km: nil, duration_min: nil, fallback: true }
  end
end