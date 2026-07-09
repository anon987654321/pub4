# frozen_string_literal: true

class FoodListingsInfiniteScrollReflex < Shared::InfiniteScrollReflex
  def load_more
    @pagy, @listings = pagy(listings_scope, page: page, request:)
    super
  end

  private

  def page_html
    @listings.map { |listing| render(partial: "food_listings/card", locals: { listing: }) }.join
  end

  def listings_scope
    scope = FoodListing.available.order(created_at: :desc)
    if element.dataset["q"].present?
      term = "%#{ActiveRecord::Base.sanitize_sql_like(element.dataset["q"])}%"
      scope = scope.where(
        "title LIKE :q OR description LIKE :q OR city LIKE :q OR dietary_info LIKE :q",
        q: term
      )
    end
    lat = element.dataset["lat"].presence
    lng = element.dataset["lng"].presence
    if lat.present? && lng.present? && scope.respond_to?(:near)
      scope = scope.near(lat, lng, element.dataset["radiusKm"].presence || 10)
    end
    scope
  end
end