# frozen_string_literal: true

module Maps
  class PlacesController < BaseController
    include Shared::LiveSearchable

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
      @place.record_activity!("PlaceViewed", source_vertical: "maps") rescue nil
    end
  end
end
