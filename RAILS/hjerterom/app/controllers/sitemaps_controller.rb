# frozen_string_literal: true

class SitemapsController < ApplicationController
  include Shared::Sitemapable

  private

  def sitemap_entries
    entries = [
      Shared::SitemapBuilder::Entry.new(loc: root_url, changefreq: "daily", priority: "1.0"),
      Shared::SitemapBuilder::Entry.new(loc: resources_url, changefreq: "daily", priority: "0.8"),
      Shared::SitemapBuilder::Entry.new(loc: food_listings_url, changefreq: "daily", priority: "0.9")
    ]

    FoodListing.available.order(updated_at: :desc).limit(2_000).each do |listing|
      entries << Shared::SitemapBuilder::Entry.new(
        loc: food_listing_url(listing),
        lastmod: listing.updated_at,
        changefreq: "daily",
        priority: "0.7"
      )
    end

    Resource.verified.order(updated_at: :desc).limit(2_000).each do |resource|
      entries << Shared::SitemapBuilder::Entry.new(
        loc: resource_url(resource),
        lastmod: resource.updated_at,
        changefreq: "monthly",
        priority: "0.6"
      )
    end

    entries
  end
end
