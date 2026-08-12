# frozen_string_literal: true

module Maps
  class PlacesController < BaseController
    include Shared::LiveSearchable

    allow_unauthenticated_access only: %i[index show]
    before_action :require_user_session, only: :check_in

    def index
      scope = Place.includes(:city, :neighborhood)
      scope = scope.where(city: Current.city_record) if Current.city_record
      scope = scope.where(kind: params[:kind]) if params[:kind].present?

      respond_to do |format|
        format.json do
          scope = apply_live_search(scope, columns: %w[name kind], vertical: "maps") if live_search_query.present?
          render json: scope.limit(200).map { |p|
            { id: p.id, name: p.name, kind: p.kind,
              lat: p.latitude, lng: p.longitude,
              city: p.city&.name, neighborhood: p.neighborhood&.name }
          }
        end
        format.html do
          scope = apply_live_search(scope, columns: %w[name kind], vertical: "maps") if live_search_query.present?
          @pagy, @places = pagy(scope.order(:name))
          finish_live_search(partial: "maps/places/live_search_results")
        end
      end
    end

    def show
      @place = Place.includes(:city, :neighborhood).find(params[:id])
      @place.record_activity!("PlaceViewed", source_vertical: "maps")
      @recent_check_ins = @place.place_check_ins.includes(:user).recent.limit(10)
      # Guests may check in (see the require_user_session gate on #check_in),
      # so the "already here" flag has to follow the same identity. With
      # authenticated? it stayed false for a guest who had just checked in and
      # the page kept offering the form.
      @checked_in = Current.user.present? && @place.place_check_ins.exists?(user: Current.user)
    end

    def check_in
      @place = Place.find(params[:id])
      check_in = @place.place_check_ins.create!(
        user: Current.user,
        note: params[:note].to_s.strip.presence,
        checked_in_at: Time.current
      )
      redirect_to place_path(@place), notice: t("flash.checked_in_at", place: @place.name)
    rescue ActiveRecord::RecordInvalid
      redirect_to place_path(@place), alert: t("flash.check_in_failed")
    end
  end
end
