# frozen_string_literal: true

module Maps
  class PlacesController < BaseController
    # "Checked in recently" means recently: a visit yesterday does not stop a
    # check-in today.
    CHECK_IN_WINDOW = 4.hours
    # A name beside "3 minutes ago" says where that person is right now, on a
    # public page. Check-ins are named once this long has passed, and counted
    # until then.
    NAMED_CHECK_IN_DELAY = 1.hour

    include Shared::LiveSearchable

    helper_method :place_kinds

    allow_unauthenticated_access only: %i[index show]
    before_action :require_user_session, only: :check_in
    # Soft guests may check in, and nothing bounded how fast they wrote rows.
    rate_limit to: 20, within: 1.hour, only: :check_in, name: "check_ins",
      with: -> { redirect_back fallback_location: root_path, alert: t("shared.flash.rate_limited") }

    def index
      scope = places_scope

      respond_to do |format|
        format.json do
          render json: scope.limit(200).map { |p|
            { id: p.id, name: p.name, kind: p.kind,
              lat: p.latitude, lng: p.longitude,
              city: p.city&.name, neighborhood: p.neighborhood&.name }
          }
        end
        # Both page formats, not html alone: finish_live_search answers a
        # turbo_stream request with its own respond_to, and an outer block that
        # had matched html for the same request raised RespondToMismatchError.
        format.any(:html, :turbo_stream) do
          @pagy, @places = pagy(scope.order(:name))
          finish_live_search(partial: "maps/places/live_search_results")
        end
      end
    end

    def show
      @place = places_in_current_city.includes(:city, :neighborhood).find(params[:id])
      @place.record_activity!("PlaceViewed", source_vertical: "maps") unless passive_request?
      load_check_ins
      # Guests may check in (see the require_user_session check on #check_in),
      # so the "already here" flag has to follow the same identity. With
      # authenticated? it stayed false for a guest who had just checked in and
      # the page kept offering the form.
      recent = @place.place_check_ins.checked_in_since(CHECK_IN_WINDOW.ago)
      @checked_in = Current.user.present? && recent.exists?(user: Current.user)
      @nearby_places = nearby_places_for(@place)
    end

    def check_in
      @place = places_in_current_city.find(params[:id])
      check_in = @place.place_check_ins.create!(
        user: Current.user,
        note: params[:note].to_s.strip.presence,
        checked_in_at: Time.current
      )
      redirect_to place_path(@place), notice: t("flash.checked_in_at", place: @place.name)
    rescue ActiveRecord::RecordInvalid
      redirect_to place_path(@place), alert: t("flash.check_in_failed")
    end

    private

    def load_check_ins
      named_before = NAMED_CHECK_IN_DELAY.ago
      check_ins = @place.place_check_ins
      named = check_ins.where(checked_in_at: ...named_before).includes(:user)
      @recent_check_ins = named.recent.limit(10)
      @unnamed_check_in_count = check_ins.checked_in_since(named_before).count
    end

    # The kinds this city actually has, for the filter: across every city it
    # offered kinds with no results here. Distinct over the city's places ran
    # on every index render and every live-search render; an hour of staleness
    # on a filter list is the right trade on a 1-vCPU box.
    def place_kinds
      Rails.cache.fetch("maps/place_kinds/#{Current.city_record&.id}", expires_in: 1.hour) do
        places_in_current_city.distinct.order(:kind).pluck(:kind).compact
      end
    end

    # The one place the list and its JSON twin decide which places match: city,
    # kind filter, then the live search.
    def places_scope
      # with_attached_photo: the card partial reads place.photo.attached? per
      # line (25 cards a page) and the live-search results do too.
      scope = places_in_current_city.includes(:city, :neighborhood).with_attached_photo
      scope = scope.where(kind: params[:kind]) if params[:kind].present?
      return scope if live_search_query.blank?

      apply_live_search(scope, columns: %w[name kind], vertical: "maps")
    end

    def nearby_places_for(place)
      return Place.none unless place.geo?

      scope = places_in_current_city.where.not(id: place.id)
      scope.nearby(place.latitude, place.longitude, 5).limit(6)
    end
  end
end
