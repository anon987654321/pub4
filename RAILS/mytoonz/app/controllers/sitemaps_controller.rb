# frozen_string_literal: true

class SitemapsController < ApplicationController
  include Shared::Sitemapable

  private

  def sitemap_entries
    entries = [Shared::SitemapBuilder::Entry.new(loc: root_url, changefreq: "daily", priority: "1.0")]
    ComicStrip.where(status: "completed").order(updated_at: :desc).limit(2_000).each do |strip|
      entries << Shared::SitemapBuilder::Entry.new(
        loc: comic_strip_url(strip),
        lastmod: strip.updated_at,
        changefreq: "monthly",
        priority: "0.6"
      )
    end
    entries
  end
end
