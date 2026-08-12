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
      entries.concat(community_entries)
      entries.concat(hashtag_entries)
    end

    entries
  end

  # ActsAsTenant already scopes CityTenantable models, but a sitemap that
  # forgets the city is how oshlo.no listed Bergen's posts. Named here so a
  # test can see the word and a future default_scope change cannot hide it.
  def in_this_city(relation)
    city = Current.city_record
    return relation.none unless city
    return relation.where(city_id: city.id) if relation.klass.column_names.include?("city_id")

    relation
  end

  def posts_entries
    in_this_city(Post.hot).limit(PER_MODEL_CAP).map do |post|
      Shared::SitemapBuilder::Entry.new(loc: post_url(post), lastmod: post.updated_at, changefreq: "daily", priority: "0.6")
    end
  end

  def community_entries
    in_this_city(Community).limit(PER_MODEL_CAP).map do |community|
      Shared::SitemapBuilder::Entry.new(loc: community_url(community), lastmod: community.updated_at, changefreq: "weekly", priority: "0.5")
    end
  end

  def hashtag_entries
    Hashtag.trending.limit([PER_MODEL_CAP, 200].min).map do |tag|
      Shared::SitemapBuilder::Entry.new(loc: hashtag_url(tag.name), lastmod: tag.updated_at, changefreq: "daily", priority: "0.4")
    end
  end

  def tv_entries
    entries = in_this_city(Tv::Channel).limit(PER_MODEL_CAP).map do |channel|
      Shared::SitemapBuilder::Entry.new(loc: tv.channel_url(channel), lastmod: channel.updated_at, changefreq: "weekly", priority: "0.6")
    end
    entries + Tv::Video.published.in_current_city.limit(PER_MODEL_CAP).map do |video|
      Shared::SitemapBuilder::Entry.new(loc: tv.video_url(video), lastmod: video.updated_at, changefreq: "monthly", priority: "0.5")
    end
  end

  def playlist_entries
    entries = Playlist::Playlist.public_playlists.limit(PER_MODEL_CAP).map do |playlist|
      Shared::SitemapBuilder::Entry.new(loc: playlist.playlist_url(playlist), lastmod: playlist.updated_at, changefreq: "weekly", priority: "0.6")
    end
    entries + Playlist::Set.publicly_listed.limit(PER_MODEL_CAP).map do |set|
      Shared::SitemapBuilder::Entry.new(loc: playlist.set_url(set), lastmod: set.updated_at, changefreq: "weekly", priority: "0.5")
    end
  end

  def takeaway_entries
    in_this_city(Takeaway::Restaurant.active).limit(PER_MODEL_CAP).map do |restaurant|
      Shared::SitemapBuilder::Entry.new(loc: takeaway.restaurant_url(restaurant), lastmod: restaurant.updated_at, changefreq: "weekly", priority: "0.7")
    end
  end

  def marketplace_entries
    entries = in_this_city(Marketplace::Store.active).limit(PER_MODEL_CAP).map do |store|
      Shared::SitemapBuilder::Entry.new(loc: marketplace.shop_url(store), lastmod: store.updated_at, changefreq: "weekly", priority: "0.6")
    end
    entries += in_this_city(Marketplace::Listing.active).limit(PER_MODEL_CAP).map do |listing|
      Shared::SitemapBuilder::Entry.new(loc: marketplace.listing_url(listing), lastmod: listing.updated_at, changefreq: "daily", priority: "0.7")
    end
    deal_rel = Marketplace::Deal.active
    deal_rel = in_this_city(deal_rel) if Marketplace::Deal.column_names.include?("city_id")
    entries + deal_rel.limit(PER_MODEL_CAP).map do |deal|
      Shared::SitemapBuilder::Entry.new(loc: marketplace.deal_url(deal), lastmod: deal.updated_at, changefreq: "daily", priority: "0.6")
    end
  end

  def maps_entries
    in_this_city(Place).limit(PER_MODEL_CAP).map do |place|
      Shared::SitemapBuilder::Entry.new(loc: maps_place_url(place), lastmod: place.updated_at, changefreq: "monthly", priority: "0.6")
    end
  end
end
