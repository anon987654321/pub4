# frozen_string_literal: true

module Maps
  class HomeController < BaseController
    allow_unauthenticated_access only: :index

    # How far ahead the map looks for events. Beyond a week a pin is clutter
    # rather than an answer to "what is on near me".
    EVENT_HORIZON = 7.days

    def index
      points = map_points
      @map_center_lat, @map_center_lng = map_center(points)
      @points_json = points.to_json
    end

    private

    # One array, four layers. The Stimulus controller styles a marker from
    # point.type and reads title/subtitle/url.
    def map_points
      places_layer + events_layer + stories_layer + courier_layer
    end

    # The city's own coordinates, else the middle of what is on the map. A city
    # with neither gets no centre at all: the map opens on the world rather
    # than on Bergen for a city that is not Bergen.
    def map_center(points)
      city = Current.city_record
      return [ city.latitude, city.longitude ] if city&.latitude.present? && city&.longitude.present?
      return [ nil, nil ] if points.empty?

      [ points.sum { |p| p[:lat] } / points.size, points.sum { |p| p[:lng] } / points.size ]
    end

    # sw_lat, sw_lng, ne_lat, ne_lng, all four or none. A bounds box that
    # crosses the antimeridian (sw_lng > ne_lng) is not filtered: no brgen city
    # sits on it, and a wrong filter would hide pins rather than add them.
    def bbox
      return @bbox if defined?(@bbox)

      values = %i[sw_lat sw_lng ne_lat ne_lng].map { |key| Float(params[key], exception: false) }
      @bbox = if values.all? { |v| v&.finite? } && values[0] <= values[2] && values[1] <= values[3]
                { latitude: values[0]..values[2], longitude: values[1]..values[3] }
      end
    end

    def within_bbox(scope)
      bbox ? scope.where(bbox) : scope
    end

    def places_layer
      scope = Place.includes(:neighborhood)
      scope = scope.where(city: Current.city_record) if Current.city_record
      within_bbox(scope).limit(500).map do |place|
        point(place.latitude, place.longitude,
              type: "place", title: place.name,
              subtitle: [ place_kind_label(place.kind), place.neighborhood&.name ].compact_blank.join(", "),
              url: place_path(place))
      end
    end

    # Events already carry coordinates — inherited from their Place or entered
    # by the organiser.
    def events_layer
      scope = Event.upcoming.includes(:neighborhood)
                   .where.not(latitude: nil)
                   .where("starts_at <= ?", Time.current + EVENT_HORIZON)
      within_bbox(scope).limit(200).map do |event|
        point(event.latitude, event.longitude,
              type: "event", title: event.title,
              subtitle: I18n.l(event.starts_at, format: :event),
              url: public_href(event))
      end
    end

    # The Snap-Map half. Story coordinates are coarsened to ~1 km when written,
    # so a pin says "around here" rather than "at this address" — which is the
    # only reason putting them on a public map is acceptable at all.
    def stories_layer
      scope = Story.alive.in_current_city.includes(:user).where.not(latitude: nil)
      within_bbox(scope).limit(200).map do |story|
        point(story.latitude, story.longitude,
              type: "story", title: story.user.display_name,
              subtitle: story.caption.to_s.truncate(60),
              url: public_href(story))
      end
    end

    # Deliberately only the viewer's own courier, and only while that order is
    # actually out for delivery. A live position is the courier's, not the
    # city's: publishing every rider's location on a public map would be
    # tracking people who never agreed to be tracked, and it is not what makes
    # the feature useful — the person waiting for the food is the only one who
    # needs it.
    def courier_layer
      return [] if Current.user.blank?

      Takeaway::Order.where(user_id: Current.user.id, status: "out_for_delivery")
                     .where.not(delivery_driver_id: nil)
                     .includes(:delivery_driver)
                     .limit(5)
                     .filter_map do |order|
                       driver = order.delivery_driver
                       next unless driver&.location?

                       point(driver.current_lat, driver.current_lng,
                             type: "courier",
                             title: I18n.t("maps.your_courier"),
                             subtitle: driver.display_name.to_s,
                             url: public_href(order))
                     end
    end

    def public_href(record)
      view_context.record_public_href(record)
    rescue StandardError # scan: intentional — an unroutable record renders unlinked
      nil
    end

    def point(lat, lng, type:, title:, subtitle:, url:)
      { type: type, title: title, subtitle: subtitle.presence, url: url,
        lat: lat.to_f, lng: lng.to_f }
    end
  end
end
