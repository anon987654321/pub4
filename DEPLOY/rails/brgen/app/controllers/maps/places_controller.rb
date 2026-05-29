# frozen_string_literal: true

module Maps
  class PlacesController < BaseController
    def index
      scope = Place.includes(:city, :neighborhood)
      scope = scope.where("name LIKE ?", "%#{params[:q]}%") if params[:q].present?
      scope = scope.where(kind: params[:kind]) if params[:kind].present?
      render json: scope.limit(200).map { |p|
        { id: p.id, name: p.name, kind: p.kind,
          lat: p.latitude, lng: p.longitude,
          city: p.city&.name, neighborhood: p.neighborhood&.name }
      }
    end

    def show
      @place = Place.includes(:city, :neighborhood).find(params[:id])
    end
  end
end
