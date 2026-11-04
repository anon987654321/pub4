# frozen_string_literal: true

class SitemapsController < ApplicationController
  include Shared::Sitemapable

  private

  def sitemap_entries
    [
      entry(root_url, changefreq: "daily", priority: "1.0"),
      entry(posts_url, changefreq: "daily", priority: "0.6"),
      *demo_entries,
      *creator_entries,
      *post_entries,
    ]
  end

  # The demo wardrobe is amber's one public catalogue: its page and each garment.
  def demo_entries
    return [] unless Amber::DemoWardrobe.available?

    items = Amber::DemoWardrobe.items.order(updated_at: :desc).limit(500)
    garments = items.map do |item|
      entry(demo_wardrobe_item_url(item), lastmod: item.updated_at, changefreq: "monthly", priority: "0.6")
    end
    [ entry(demo_wardrobe_url, changefreq: "weekly", priority: "0.8"), *garments ]
  end

  def creator_entries
    CreatorProfile.publicly_visible.order(updated_at: :desc).limit(2_000).map do |profile|
      entry(creator_profile_url(profile.handle), lastmod: profile.updated_at, changefreq: "weekly", priority: "0.7")
    end
  end

  def post_entries
    Post.order(updated_at: :desc).limit(2_000).map do |post|
      entry(post_url(post), lastmod: post.updated_at, changefreq: "monthly", priority: "0.5")
    end
  end

  def entry(loc, **attributes)
    Shared::SitemapBuilder::Entry.new(loc:, **attributes)
  end
end
