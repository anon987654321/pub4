# frozen_string_literal: true

class SitemapsController < ApplicationController
  include Shared::Sitemapable

  private

  def sitemap_entries
    entries = [Shared::SitemapBuilder::Entry.new(loc: root_url, changefreq: "daily", priority: "1.0")]

    Video.order(updated_at: :desc).limit(2_000).each do |video|
      entries << Shared::SitemapBuilder::Entry.new(
        loc: video_url(video),
        lastmod: video.updated_at,
        changefreq: "weekly",
        priority: "0.6"
      )
    end

    entries
  end
end