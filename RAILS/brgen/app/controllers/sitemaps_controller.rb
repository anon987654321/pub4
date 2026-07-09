# frozen_string_literal: true

class SitemapsController < ApplicationController
  include Shared::Sitemapable

  # One route serves every city domain and every vertical subdomain — the
  # active subapp is resolved the same way the rest of the app resolves it
  # (Brgen::DomainRegistry), so this needs no per-subdomain route wiring.
  PER_MODEL_CAP = 2_000

  private

  def sitemap_entries
    subapp = Brgen::DomainRegistry.resolve(request.host).subapp
    entries = [Shared::SitemapBuilder::Entry.new(loc: root_url, changefreq: "daily", priority: "1.0")]

    case subapp
    when :tv then entries.concat(tv_entries)
    when :playlist then entries.concat(playlist_entries)
    when :takeaway then entries.concat(takeaway_entries)
    when :marketplace then entries.concat(marketplace_entries)
    when :maps then entries.concat(maps_entries)
    when :dating, :messenger, :ai
      # Personal profiles and private conversations are never indexed — root only.
    else
      entries.concat(posts_entries)
    end

    entries
  end

  def posts_entries
    Post.hot.limit(PER_MODEL_CAP).map do |post|
      Shared::SitemapBuilder::Entry.new(loc: post_url(post), lastmod: post.updated_at, changefreq: "daily", priority: "0.6")
    end
  end

  def tv_entries
    entries = Tv::Channel.limit(PER_MODEL_CAP).map do |channel|
      Shared::SitemapBuilder::Entry.new(loc: tv_channel_url(channel), lastmod: channel.updated_at, changefreq: "weekly", priority: "0.6")
    end
    entries + Tv::Video.published.limit(PER_MODEL_CAP).map do |video|
      Shared::SitemapBuilder::Entry.new(loc: tv_video_url(video), lastmod: video.updated_at, changefreq: "monthly", priority: "0.5")
    end
  end

  def playlist_entries
    entries = Playlist::Playlist.public_playlists.limit(PER_MODEL_CAP).map do |playlist|
      Shared::SitemapBuilder::Entry.new(loc: playlist_playlist_url(playlist), lastmod: playlist.updated_at, changefreq: "weekly", priority: "0.6")
    end
    entries + Playlist::Set.publicly_listed.limit(PER_MODEL_CAP).map do |set|
      Shared::SitemapBuilder::Entry.new(loc: playlist_set_url(set), lastmod: set.updated_at, changefreq: "weekly", priority: "0.5")
    end
  end

  def takeaway_entries
    Takeaway::Restaurant.active.limit(PER_MODEL_CAP).map do |restaurant|
      Shared::SitemapBuilder::Entry.new(loc: takeaway_restaurant_url(restaurant), lastmod: restaurant.updated_at, changefreq: "weekly", priority: "0.7")
    end
  end

  def marketplace_entries
    entries = Marketplace::Store.active.limit(PER_MODEL_CAP).map do |store|
      Shared::SitemapBuilder::Entry.new(loc: marketplace_shop_url(store), lastmod: store.updated_at, changefreq: "weekly", priority: "0.6")
    end
    entries += Marketplace::Listing.active.limit(PER_MODEL_CAP).map do |listing|
      Shared::SitemapBuilder::Entry.new(loc: marketplace_listing_url(listing), lastmod: listing.updated_at, changefreq: "daily", priority: "0.7")
    end
    entries + Marketplace::Deal.active.limit(PER_MODEL_CAP).map do |deal|
      Shared::SitemapBuilder::Entry.new(loc: marketplace_deal_url(deal), lastmod: deal.updated_at, changefreq: "daily", priority: "0.6")
    end
  end

  def maps_entries
    Place.limit(PER_MODEL_CAP).map do |place|
      Shared::SitemapBuilder::Entry.new(loc: maps_place_url(place), lastmod: place.updated_at, changefreq: "monthly", priority: "0.6")
    end
  end
end
