# frozen_string_literal: true

class HomeController < ApplicationController
  ÅSANE_CENTER = { lat: 60.4669, lng: 5.3256 }.freeze

  allow_unauthenticated_access only: :index

  def index
    @crisis_lines  = Crisis.where(available_24h: true).limit(5)
    @food_listings = FoodListing.available.order(created_at: :desc).limit(20)
    @posts         = Post.recent.includes(:user, :category).limit(5)
    @resources     = Resource.verified.limit(20)
    @mapbox_token  = mapbox_token
    @map_points    = map_points
  end

  private

  def mapbox_token
    ENV["MAPBOX_API_KEY"].presence
  end

  def map_points
    food_points + resource_points
  end

  def food_points
    @food_listings.filter_map do |listing|
      lat = listing.latitude || ÅSANE_CENTER[:lat]
      lng = listing.longitude || ÅSANE_CENTER[:lng]
      {
        type: "food",
        title: listing.title,
        subtitle: [ listing.city, listing.available_until&.strftime("%b %-d") ].compact.join(" · "),
        url: food_listing_path(listing),
        lat: lat,
        lng: lng
      }
    end
  end

  def resource_points
    @resources.filter_map do |resource|
      lat = resource.latitude || ÅSANE_CENTER[:lat]
      lng = resource.longitude || ÅSANE_CENTER[:lng]
      {
        type: "resource",
        title: resource.title,
        subtitle: [ resource.resource_type&.humanize, resource.city ].compact.join(" · "),
        url: resource_path(resource),
        lat: lat,
        lng: lng
      }
    end
  end
end
