# frozen_string_literal: true

module Shared
  # How far away something was written.
  #
  # Borrowed from Jodel, which stamps every post with its distance and is the
  # reason its feed reads as a place rather than a list. brgen already had both
  # halves and rendered neither: Post includes Shared::GeoLocatable, so
  # distance_to has always worked, and stamp_live_location! has been coarsening
  # coordinates to two decimals since Live shipped.
  #
  # That coarsening is why this never prints a decimal. Two decimals of latitude
  # is roughly a kilometre, so "1.4 km" would state a precision the stored value
  # does not have — the number would be arithmetic on a rounded figure, presented
  # as a measurement. Under a kilometre says so in words; past that it is whole
  # kilometres, and past the Live radius it says nothing at all rather than
  # inviting someone to triangulate.
  module PlaceHelper
    NEAR_KM = 1
    FAR_KM = 20

    def distance_stamp(record, viewer: Current.user)
      km = distance_km(record, viewer)
      return nil if km.nil? || km > FAR_KM

      if km < NEAR_KM
        t("place.within_a_km")
      else
        t("place.km_away", count: km.round)
      end
    end

    private

    def distance_km(record, viewer)
      return nil unless record.respond_to?(:distance_to)
      return nil unless viewer&.latitude && viewer&.longitude

      record.distance_to(viewer.latitude, viewer.longitude)&.to_f
    end
  end
end
