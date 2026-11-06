# frozen_string_literal: true

class SitemapsController < ApplicationController
  include Shared::Sitemapable

  # The full ports tree is ~11-12k entries — comfortably under the 50,000
  # sitemaps.org per-file limit, so a single file needs no sitemap index.
  MAX_PORTS = 20_000

  # Every crawler hit rebuilt ~14k entries - three full-table loads and a
  # route-helper call each - to hand the same answer to the next crawler.
  # An hour of staleness is far inside every changefreq here, and the host
  # is in the key because a sitemap may only carry its own host's URLs.
  SITEMAP_TTL = 1.hour

  private

  def sitemap_entries
    Rails.cache.fetch("sitemap/entries/#{request.host}", expires_in: SITEMAP_TTL) do
      entries = [
        Shared::SitemapBuilder::Entry.new(loc: root_url, changefreq: "daily", priority: "1.0"),
        Shared::SitemapBuilder::Entry.new(loc: categories_url, changefreq: "weekly", priority: "0.7")
      ]

      Category.find_each do |category|
        entries << Shared::SitemapBuilder::Entry.new(loc: category_url(category), changefreq: "weekly", priority: "0.6")
      end

      # maintainers#show is public and crawlable, and was missing here.
      Maintainer.find_each do |maintainer|
        entries << Shared::SitemapBuilder::Entry.new(loc: maintainer_url(maintainer), changefreq: "weekly",
                                                     priority: "0.4")
      end

      entries.concat(port_entries)
    end
  end

  # lastmod is the ports-tree date: updated_at moves for all 12k ports on
  # every re-import, which told crawlers the whole tree changed each night.
  def port_entries
    ports = Port.order(Arel.sql("last_updated IS NULL, last_updated DESC"))
    ports.limit(MAX_PORTS).map do |port|
      Shared::SitemapBuilder::Entry.new(
        loc: port_url(port),
        lastmod: port.last_updated || port.updated_at,
        changefreq: "weekly",
        priority: "0.6"
      )
    end
  end
end
