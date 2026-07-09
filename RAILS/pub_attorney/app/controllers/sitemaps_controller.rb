# frozen_string_literal: true

class SitemapsController < ApplicationController
  include Shared::Sitemapable

  private

  def sitemap_entries
    entries = [Shared::SitemapBuilder::Entry.new(loc: root_url, changefreq: "daily", priority: "1.0")]

    Lawyer.order(updated_at: :desc).limit(2_000).each do |lawyer|
      entries << Shared::SitemapBuilder::Entry.new(
        loc: lawyer_url(lawyer),
        lastmod: lawyer.updated_at,
        changefreq: "monthly",
        priority: "0.7"
      )
    end

    Case.order(updated_at: :desc).limit(2_000).each do |kase|
      entries << Shared::SitemapBuilder::Entry.new(
        loc: case_url(kase),
        lastmod: kase.updated_at,
        changefreq: "weekly",
        priority: "0.6"
      )
    end

    entries
  end
end