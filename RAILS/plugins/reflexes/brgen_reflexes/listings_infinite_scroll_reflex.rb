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

  # The filters and the order page one applied, read back from the sentinel, so
  # page two is the same list in the same order. It used to come back newest
  # first and unfiltered by condition or price, under a page sorted by price.
  def scope
    data = element.dataset
    scope = Marketplace::Listing.publicly_visible.includes(:user, :category)
                                .where(kind: Marketplace::Listing.kind_from(data["kind"]))
    scope = by_source(scope, data)
    scope = by_price(scope, data)
    by_place(searched(scope), data).sorted_by(data["sort"].presence || "rank")
  end

  def by_source(scope, data)
    scope = scope.where(category_id: data["categoryId"]) if data["categoryId"].present?
    scope = scope.where(condition: data["condition"]) if data["condition"].present?
    case data["from"]
    when "person" then scope.casual
    when "shop" then scope.from_shops
    else scope
    end
  end

  def by_price(scope, data)
    scope = scope.where("price_cents >= ?", (data["minPrice"].to_f * 100).to_i) if data["minPrice"].present?
    scope = scope.where("price_cents <= ?", (data["maxPrice"].to_f * 100).to_i) if data["maxPrice"].present?
    scope
  end

  def searched(scope)
    term = like_term
    term ? scope.where("title LIKE ? OR description LIKE ? OR location LIKE ?", term, term, term) : scope
  end

  def by_place(scope, data)
    lat = data["lat"].presence
    lng = data["lng"].presence
    return scope unless lat && lng

    scope.near(lat, lng, Marketplace::Listing.radius_from(data["radiusKm"].presence))
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
