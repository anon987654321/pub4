# frozen_string_literal: true

class SitemapsController < ApplicationController
  include Shared::Sitemapable

  # One route serves every city domain and every vertical subdomain — the
  # active subapp is resolved the same way the rest of the app resolves it
  # (Brgen::DomainRegistry), so this needs no per-subdomain route wiring.
  PER_MODEL_CAP = 2_000
  # Trending is an aggregate over the whole tagging window, not a page of rows —
  # it earns a tighter cap than the per-model one.
  HASHTAG_CAP = 200

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
      entries.concat(community_entries)
      entries.concat(hashtag_entries)
      entries.concat(user_entries)
    end

    entries
  end

  # in_current_city is the city scoping, and it lives on the models: CityScoped
  # for the ones with their own city_id, TenantedThrough for Tv::Video and
  # Marketplace::Deal, which have none and reach a city through a parent. It is
  # written at every call site rather than left to acts_as_tenant's default
  # scope because a sitemap that forgets the city is how oshlo.no listed
  # Bergen's posts, and a default_scope is not something a reader can see.
  def entries_for(relation, changefreq:, priority:, cap: PER_MODEL_CAP)
    # A cached collection arrives already limited and as an Array.
    relation = relation.limit(cap) if relation.respond_to?(:limit)
    relation.map do |record|
      Shared::SitemapBuilder::Entry.new(loc: yield(record), lastmod: record.updated_at,
                                        changefreq: changefreq, priority: priority)
    end
  end

  def posts_entries
    entries_for(Post.hot.in_current_city, changefreq: "daily", priority: "0.6") { |p| post_url(p) }
  end

  def community_entries
    entries_for(Community.in_current_city, changefreq: "weekly", priority: "0.5") { |c| community_url(c) }
  end

  # Public profiles whose home-city hint is this city. User is not a tenant row
  # and its in_current_city is strict about nil city_id — see the scope.
  # Dating/messenger stay unsitemapped.
  def user_entries
    entries_for(User.public_profiles.in_current_city, changefreq: "weekly", priority: "0.4") { |u| user_url(u) }
  end

  # Hashtags are global by design — a tag is not a city's property. Which is
  # also why one cache entry serves every host: trending is a JOIN + GROUP BY +
  # ORDER BY COUNT(*) over the whole tagging window, and it was recomputed on
  # every crawler hit on all 44 domains for a result none of them varied.
  # Community.popular_cached is the same medicine for the same query shape.
  def hashtag_entries
    tags = Rails.cache.fetch("sitemap/hashtags/#{HASHTAG_CAP}", expires_in: 1.hour) do
      Hashtag.trending.limit(HASHTAG_CAP).to_a
    end
    entries_for(tags, changefreq: "daily", priority: "0.4", cap: HASHTAG_CAP) { |t| hashtag_url(t.name) }
  end

  def tv_entries
    entries_for(Tv::Channel.in_current_city, changefreq: "weekly", priority: "0.6") { |c| tv.channel_url(c) } +
      entries_for(Tv::Video.published.in_current_city, changefreq: "monthly", priority: "0.5") { |v| tv.video_url(v) }
  end

  def playlist_entries
    entries_for(Playlist::Playlist.public_playlists, changefreq: "weekly", priority: "0.6") { |p| playlist.playlist_url(p) } +
      entries_for(Playlist::Set.publicly_listed, changefreq: "weekly", priority: "0.5") { |s| playlist.set_url(s) }
  end

  def takeaway_entries
    entries_for(Takeaway::Restaurant.active.in_current_city, changefreq: "weekly", priority: "0.7") { |r| takeaway.restaurant_url(r) }
  end

  def marketplace_entries
    entries_for(Marketplace::Store.active.in_current_city, changefreq: "weekly", priority: "0.6") { |s| marketplace.shop_url(s) } +
      entries_for(Marketplace::Listing.live.in_current_city, changefreq: "daily", priority: "0.7") { |l| marketplace.listing_url(l) } +
      entries_for(Marketplace::Deal.live.in_current_city, changefreq: "daily", priority: "0.6") { |d| marketplace.deal_url(d) }
  end

  def maps_entries
    entries_for(Place.in_current_city, changefreq: "monthly", priority: "0.6") { |p| maps.place_url(p) }
  end
end
