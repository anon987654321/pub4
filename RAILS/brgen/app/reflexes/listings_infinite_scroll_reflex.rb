# frozen_string_literal: true

class ListingsInfiniteScrollReflex < Shared::InfiniteScrollReflex
  def load_more
    @pagy, @listings = pagy(listings_scope, page: page, request:)
    @listing_distances = listing_distances(
      @listings,
      element.dataset["lat"].presence,
      element.dataset["lng"].presence
    )
    super
  end

  private

  def page_html
    @listings.map do |listing|
      render(
        partial: "marketplace/listings/card",
        locals: {
          listing: listing,
          distance_km: @listing_distances&.fetch(listing.id, nil)
        }
      )
    end.join
  end

  def listings_scope
    scope = Marketplace::Listing.includes(:user, :category).recent
    scope = scope.where(category_id: element.dataset["categoryId"]) if element.dataset["categoryId"].present?
    if element.dataset["q"].present?
      term = "%#{ActiveRecord::Base.sanitize_sql_like(element.dataset["q"])}%"
      scope = scope.where("title LIKE ? OR description LIKE ? OR location LIKE ?", term, term, term)
    end
    lat = element.dataset["lat"].presence
    lng = element.dataset["lng"].presence
    if lat.present? && lng.present?
      radius = Marketplace::Listing.radius_from(element.dataset["radiusKm"].presence)
      scope = scope.near(lat, lng, radius)
    end
    scope
  end

  def listing_distances(listings, lat, lng)
    return {} if lat.blank? || lng.blank?

    listings.each_with_object({}) do |listing, distances|
      distances[listing.id] =
        if listing.latitude.blank? || listing.longitude.blank?
          nil
        else
          listing.distance_to(lat.to_f, lng.to_f)
        end
    end
  end
end