# frozen_string_literal: true

class ListingsInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "marketplace/listings/card", as: :listing

  private

  # Distances are computed once for the page, between pagination and rendering,
  # rather than per row inside the partial.
  #
  # The version this replaces assigned the distance hash over @listings -- the
  # same ivar it had just paginated into -- and then read `@listings&.fetch(id)`
  # while mapping over @listings. It worked only because the map had already
  # captured the array; one more read of the ivar anywhere in that method would
  # have been reading the hash.
  def after_paginate
    @distances = listing_distances(
      @records,
      element.dataset["lat"].presence,
      element.dataset["lng"].presence
    )
  end

  def row_locals(record)
    { listing: record, distance_km: @distances[record.id] }
  end

  def scope
    scope = Marketplace::Listing.live.includes(:user, :category).recent
    scope = scope.where(category_id: element.dataset["categoryId"]) if element.dataset["categoryId"].present?
    scope = scope.casual if element.dataset["from"] == "person"
    scope = scope.from_shops if element.dataset["from"] == "shop"
    if (term = like_term)
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
