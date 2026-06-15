# frozen_string_literal: true

module Brgen
  class GlobalSearch
    Result = Data.define(:type, :id, :title, :subtitle, :url, :record)

    def self.call(query:, limit: 8, actor: nil, locality: nil)
      new(query:, limit:, actor:, locality:).call
    end

    def initialize(query:, limit: 8, actor: nil, locality: nil)
      @query = query.to_s.strip
      @limit = limit
      @actor = actor
      @locality = locality
    end

    def call
      return empty_response if query.empty?

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      groups = {
        marketplace: search_marketplace,
        playlist_sets: search_playlist_sets,
        playlist_tracks: search_playlist_tracks,
        tv_videos: search_tv_videos,
        tv_channels: search_tv_channels,
        takeaway: search_takeaway,
        posts: search_posts,
        places: search_places,
      }
      results = groups.values.flatten
      count = results.size
      latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      suggestions = count.zero? ? Shared::SearchSuggestions.for(query, vertical: "global") : []

      Shared::SearchAnalytics.log(
        query: query,
        result_count: count,
        latency_ms: latency_ms,
        vertical: "global",
        actor: actor,
        app: "brgen",
        locality: locality
      )

      {
        query: query,
        results: results,
        groups: groups,
        result_count: count,
        latency_ms: latency_ms,
        suggestions: suggestions,
      }
    end

    private

    attr_reader :query, :limit, :actor, :locality

    def empty_response
      { query: "", results: [], groups: {}, result_count: 0, latency_ms: 0, suggestions: [] }
    end

    def search_marketplace
      Marketplace::Listing.active.search(query).recent.limit(limit).map do |listing|
        Result.new(
          type: "marketplace",
          id: listing.id,
          title: listing.title,
          subtitle: listing.location,
          url: "/markedsplass/listings/#{listing.id}",
          record: listing
        )
      end
    rescue StandardError
      []
    end

    def search_playlist_sets
      Playlist::Set.publicly_listed.search(query).order(created_at: :desc).limit(limit).map do |set|
        Result.new(
          type: "playlist_set",
          id: set.id,
          title: set.name,
          subtitle: "Set",
          url: "/playlist/sets/#{set.id}",
          record: set
        )
      end
    rescue StandardError
      []
    end

    def search_playlist_tracks
      Playlist::Track.publicly_visible.search(query).recent.limit(limit).map do |track|
        Result.new(
          type: "playlist_track",
          id: track.id,
          title: track.title,
          subtitle: [track.artist, track.genre].compact.join(" · "),
          url: "/playlist/tracks/#{track.id}",
          record: track
        )
      end
    rescue StandardError
      []
    end

    def search_tv_videos
      Tv::Video.published.search(query).recent.limit(limit).map do |video|
        Result.new(
          type: "tv_video",
          id: video.id,
          title: video.title,
          subtitle: video.channel&.name,
          url: "/tv/videos/#{video.id}",
          record: video
        )
      end
    rescue StandardError
      []
    end

    def search_tv_channels
      Tv::Channel.search(query).popular.limit(limit).map do |channel|
        Result.new(
          type: "tv_channel",
          id: channel.id,
          title: channel.name,
          subtitle: "Channel",
          url: "/tv/channels/#{channel.slug}",
          record: channel
        )
      end
    rescue StandardError
      []
    end

    def search_takeaway
      Takeaway::Restaurant.active.search(query).popular.limit(limit).map do |restaurant|
        Result.new(
          type: "takeaway",
          id: restaurant.id,
          title: restaurant.name,
          subtitle: [restaurant.cuisine_type, restaurant.city].compact.join(" · "),
          url: "/takeaway/restaurants/#{restaurant.id}",
          record: restaurant
        )
      end
    rescue StandardError
      []
    end

    def search_posts
      Post.search(query).fresh.limit(limit).map do |post|
        Result.new(
          type: "post",
          id: post.id,
          title: post.title,
          subtitle: "Post",
          url: "/posts/#{post.id}",
          record: post
        )
      end
    rescue StandardError
      []
    end

    def search_places
      Place.search(query).includes(:city, :neighborhood).limit(limit).map do |place|
        Result.new(
          type: "place",
          id: place.id,
          title: place.name,
          subtitle: [place.kind, place.neighborhood&.name].compact.join(" · "),
          url: "/maps/places/#{place.id}",
          record: place
        )
      end
    rescue StandardError
      []
    end
  end
end