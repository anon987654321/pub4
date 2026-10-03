# frozen_string_literal: true

class SitemapsController < ApplicationController
  include Shared::Sitemapable

  private

  def sitemap_entries
    entries = [ Shared::SitemapBuilder::Entry.new(loc: root_url, changefreq: "daily", priority: "1.0") ]

    CreatorProfile.publicly_visible.order(updated_at: :desc).limit(2_000).each do |profile|
      entries << Shared::SitemapBuilder::Entry.new(
        loc: creator_profile_url(profile.handle),
        lastmod: profile.updated_at,
        changefreq: "weekly",
        priority: "0.7"
      )
    end

    Post.order(updated_at: :desc).limit(2_000).each do |post|
      entries << Shared::SitemapBuilder::Entry.new(
        loc: post_url(post),
        lastmod: post.updated_at,
        changefreq: "monthly",
        priority: "0.5"
      )
    end

    entries
  end
end
