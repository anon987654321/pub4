# frozen_string_literal: true

module Shared
  class GeoIsolation
    @mutex = Mutex.new

    def self.compute_isolated_bounds(coordinates)
      @mutex.synchronize do
        raise ArgumentError, "Malformed coordinate matrix" unless coordinates.is_a?(Hash)

        lat = coordinates[:latitude].to_f
        lng = coordinates[:longitude].to_f
        { status: :secure, bounds: [ lat.round(4), lng.round(4) ] }
      rescue StandardError => e
        { status: :error, message: e.message }
      end
    end
  end
end
