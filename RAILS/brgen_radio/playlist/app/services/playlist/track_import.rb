# frozen_string_literal: true

require "uri"

module Playlist
  class TrackImport
    Result = Struct.new(:track, :line, :created, keyword_init: true)

    def initialize(user:, playlist:, whyp_embed_resolver: ::Playlist::WhypEmbedResolver.new)
      @user = user
      @playlist = playlist
      @whyp_embed_resolver = whyp_embed_resolver
    end

    def call(text)
      text.to_s.lines.map(&:strip).reject(&:blank?).filter_map do |line|
        import_line(line)
      end
    end

    private

    attr_reader :user, :playlist, :whyp_embed_resolver

    def import_line(line)
      attrs = attributes_for(line)
      existing = ::Playlist::Track.find_by(source_url: attrs[:source_url])
      track = existing if existing&.visible_to?(user)
      created = track.nil?
      track ||= ::Playlist::Track.new(attrs.merge(user: user))
      if created
        track.assign_attributes(attrs)
      elsif attrs[:embed_url].present? && track.has_attribute?(:embed_url) && track.embed_url.blank?
        track.embed_url = attrs[:embed_url]
      end
      track.save!
      playlist.add_track!(track, user: user)
      Result.new(track: track, line: line, created: created)
    rescue URI::InvalidURIError, ActiveRecord::RecordInvalid
      nil
    end

    def attributes_for(line)
      uri = URI.parse(line)
      host = uri.host.to_s.downcase
      source_type = source_type_for(host)
      title = title_for(uri, source_type)

      attributes = {
        title: title,
        artist: "Imported",
        source_type: source_type,
        source_url: line,
        privacy: "public",
      }
      if source_type == "whyp"
        embed_url = whyp_embed_resolver.call(line)
        attributes[:embed_url] = embed_url if embed_url.present?
      end
      attributes
    end

    # Hosts compared whole, never by substring — matching Shared::LinkEmbed's
    # rule, so a lookalike host (youtube.com.evil.test, notyoutube.com) files
    # as "direct" rather than as the provider it merely names.
    YOUTUBE_HOSTS = %w[youtube.com www.youtube.com m.youtube.com youtu.be].freeze
    SPOTIFY_HOSTS = %w[open.spotify.com spotify.com].freeze
    SOUNDCLOUD_HOSTS = %w[soundcloud.com www.soundcloud.com m.soundcloud.com].freeze
    WHYP_HOSTS = %w[whyp.it www.whyp.it].freeze

    def source_type_for(host)
      return "youtube" if YOUTUBE_HOSTS.include?(host)
      return "spotify" if SPOTIFY_HOSTS.include?(host)
      return "soundcloud" if SOUNDCLOUD_HOSTS.include?(host)
      return "whyp" if WHYP_HOSTS.include?(host)

      "direct"
    end

    def title_for(uri, source_type)
      case source_type
      when "youtube"
        query = Rack::Utils.parse_query(uri.query)
        "YouTube #{query["v"].presence || File.basename(uri.path)}"
      when "spotify"
        "Spotify #{uri.path.split("/").reject(&:blank?).last}"
      when "soundcloud"
        uri.path.split("/").reject(&:blank?).last.to_s.tr("-", " ").titleize.presence || "SoundCloud track"
      when "whyp"
        id = uri.path.split("/").last
        "Track ##{id}"
      else
        File.basename(uri.path).presence || uri.host
      end
    end
  end
end
