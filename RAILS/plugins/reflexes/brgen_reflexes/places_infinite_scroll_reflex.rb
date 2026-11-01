# frozen_string_literal: true

class PlacesInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "maps/places/card", as: :place

  private

  def scope
    scope = Place.includes(:city, :neighborhood).order(:name)
    scope = scope.where(kind: element.dataset["kind"]) if element.dataset["kind"].present?
    if element.dataset["q"].present?
      term = "%#{ActiveRecord::Base.sanitize_sql_like(element.dataset["q"])}%"
      scope = scope.where("name LIKE ? OR kind LIKE ?", term, term)
    end
    scope
  end
end
