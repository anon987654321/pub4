# frozen_string_literal: true

class Conversation
  # Anonymous, radius-scoped group room — same public/anonymous/disappearing
  # machinery as the channels, but bucketed by a ~10km geo grid cell instead
  # of by city. Soft guests and signed-in users both join (NearbyController
  # stores lat/lng on Current.user after the browser grants geolocation).
  # Not seeded with bots — meant to read as people actually nearby, not an
  # always-on lobby. Empty cells are normal; the city #brgen channel is the
  # no-GPS anonymous chat fallback.
  module GeoRooms
    extend ActiveSupport::Concern

    GEO_ROOM_RADIUS_KM = 10.0
    GEO_ROOM_SLUG_PREFIX = "nearby-"

    class_methods do
      def geo_room_slug?(slug) = slug.to_s.start_with?(GEO_ROOM_SLUG_PREFIX)

      def find_or_create_geo_room(lat:, lng:)
        slug = "#{GEO_ROOM_SLUG_PREFIX}#{Shared::GeoLocatable.cell_id(lat: lat, lng: lng, km: GEO_ROOM_RADIUS_KM)}"
        # city_id is always nil — scope without tenant so a city tenant cannot hide
        # an existing cross-city cell room.
        ActsAsTenant.without_tenant do
          find_by(slug: slug, city_id: nil) || create_geo_room!(slug)
        end
      end

      def create_geo_room!(slug)
        create!(conversation_type: "group", slug: slug, city_id: nil, name: "Nearby chat",
                disappearing_duration: Conversation::CHANNEL_TTL)
      rescue ActiveRecord::RecordNotUnique
        # Two nearby visitors opened a fresh room in the same cell at once.
        ActsAsTenant.without_tenant { find_by!(slug: slug, city_id: nil) }
      end
    end
  end
end
