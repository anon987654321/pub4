# frozen_string_literal: true

require "uri"

module Playlist
  class TrackImport
    Result = Struct.new(:track, :line, :created, keyword_init: true)

    def initialize(user:, playlist:)
      @user = user
      @playlist = playlist
    end

    def call(text)
      text.to_s.lines.map(&:strip).reject(&:blank?).filter_map do |line|
        import_line(line)
      end
    end

    private

    attr_reader :user, :playlist

    def import_line(line)
      attrs = attributes_for(line)
      existing = ::Playlist::Track.find_by(source_url: attrs[:source_url])
      track = existing if existing&.visible_to?(user)
      created = track.nil?
      track ||= ::Playlist::Track.new(attrs.merge(user: user))
      track.assign_attributes(attrs) if created
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

      {
        title: title,
        artist: "Imported",
        source_type: source_type,
        source_url: line,
        privacy: "public"
      }
    end

    def source_type_for(host)
      return "youtube" if host.include?("youtube.com") || host.include?("youtu.be")
      return "spotify" if host.include?("spotify.com")
      return "soundcloud" if host.include?("soundcloud.com")
      return "whyp" if host.include?("whyp.it")

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
