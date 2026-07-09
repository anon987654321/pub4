# frozen_string_literal: true

module Maps
  class PlacesController < BaseController
    include Shared::LiveSearchable

    allow_unauthenticated_access only: %i[index show]
    before_action :require_real_user, only: :check_in

    def index
      scope = Place.includes(:city, :neighborhood)
      scope = apply_live_search(scope, columns: %w[name kind], vertical: "maps") if live_search_query.present?
      scope = scope.where(kind: params[:kind]) if params[:kind].present?
      render json: scope.limit(200).map { |p|
        { id: p.id, name: p.name, kind: p.kind,
          lat: p.latitude, lng: p.longitude,
          city: p.city&.name, neighborhood: p.neighborhood&.name }
      }
    end

    def show
      @place = Place.includes(:city, :neighborhood).find(params[:id])
      @place.record_activity!("PlaceViewed", source_vertical: "maps")
      @recent_check_ins = @place.place_check_ins.includes(:user).recent.limit(10)
      @checked_in = authenticated? && @place.place_check_ins.exists?(user: Current.user)
    end

    def check_in
      @place = Place.find(params[:id])
      check_in = @place.place_check_ins.create!(
        user: Current.user,
        note: params[:note].to_s.strip.presence,
        checked_in_at: Time.current
      )
      redirect_to maps_place_path(@place), notice: "Checked in at #{@place.name}"
    rescue ActiveRecord::RecordInvalid
      redirect_to maps_place_path(@place), alert: "Could not check in"
    end
  end
end
