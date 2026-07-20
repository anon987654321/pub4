# frozen_string_literal: true

class PlacesInfiniteScrollReflex < Shared::InfiniteScrollReflex
  def load_more
    @pagy, @places = pagy(places_scope, page: page, request:)
    super
  end

  private

  def page_html
    @places.map do |place|
      render(partial: "maps/places/card", locals: { place: })
    end.join
  end

  def places_scope
    scope = Place.includes(:city, :neighborhood).order(:name)
    scope = scope.where(kind: element.dataset["kind"]) if element.dataset["kind"].present?
    if element.dataset["q"].present?
      term = "%#{ActiveRecord::Base.sanitize_sql_like(element.dataset["q"])}%"
      scope = scope.where("name LIKE ? OR kind LIKE ?", term, term)
    end
    scope
  end
end
