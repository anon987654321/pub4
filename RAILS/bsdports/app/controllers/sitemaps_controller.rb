# frozen_string_literal: true

class SitemapsController < ApplicationController
  include Shared::Sitemapable

  # The full ports tree is ~11-12k entries — comfortably under the 50,000
  # sitemaps.org per-file limit, so a single file needs no sitemap index.
  MAX_PORTS = 20_000

  private

  def sitemap_entries
    entries = [
      Shared::SitemapBuilder::Entry.new(loc: root_url, changefreq: "daily", priority: "1.0"),
      Shared::SitemapBuilder::Entry.new(loc: categories_url, changefreq: "weekly", priority: "0.7")
    ]

    Category.find_each do |category|
      entries << Shared::SitemapBuilder::Entry.new(loc: category_url(category), changefreq: "weekly", priority: "0.6")
    end

    Port.order(updated_at: :desc).limit(MAX_PORTS).each do |port|
      entries << Shared::SitemapBuilder::Entry.new(
        loc: port_url(port),
        lastmod: port.updated_at,
        changefreq: "weekly",
        priority: "0.6"
      )
    end

    entries
  end
end
