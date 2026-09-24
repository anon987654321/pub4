# frozen_string_literal: true

require "yaml"

module Playlist
  class RadioCollectionSeeder
    CONFIG_PATH = Rails.root.join("config/radio/collection.yml")
    MANIFEST_PATH = Rails.root.join("config/radio/imported_tracks.yml")

    Result = Data.define(:cities, :tracks, :attached, :skipped)

    class << self
      def seed!
        new.seed!
      end
    end

    def initialize(config_path: CONFIG_PATH, manifest_path: MANIFEST_PATH)
      @config_path = Pathname(config_path)
      @manifest_path = Pathname(manifest_path)
    end

    def seed!
      return Result.new(cities: [], tracks: 0, attached: 0, skipped: 0) unless @manifest_path.file?

      config = load_yaml(@config_path)
      manifest = load_yaml(@manifest_path)
      rows = Array(manifest["tracks"])
      domains = Array(config["target_domains"]).filter_map(&:presence)
      counts = { tracks: 0, attached: 0, skipped: 0 }

      cities = domains.filter_map do |domain|
        city = City.find_by(domain: domain)
        next unless city

        ActsAsTenant.with_tenant(city) do
          owner = radio_owner(city)
          next unless owner

          playlist = find_or_create_playlist!(city, owner)
          rows.each do |row|
            next unless row.is_a?(Hash)

            track, attached = seed_track!(row, owner)
            counts[:skipped] += 1 and next unless track

            playlist.add_track!(track, user: owner)
            counts[:tracks] += 1
            counts[:attached] += 1 if attached
          end
          playlist.update_column(:tracks_count, playlist.tracks.count) if playlist.tracks_count != playlist.tracks.count
        end

        city
      end

      Result.new(cities:, **counts)
    end

    private

    def load_yaml(path)
      return {} unless path.file?

      YAML.safe_load_file(path, aliases: true) || {}
    end

    def radio_owner(city)
      User.find_by(email_address: "admin@#{city.domain}") ||
        User.where(city: city).order(:id).first
    end

    def find_or_create_playlist!(city, owner)
      name = "Radio #{city.name}"
      playlist = Playlist::Playlist.find_or_initialize_by(city: city, name: name, user: owner)
      playlist.assign_attributes(
        description: "Local radio from #{city.name}. Tracks imported from the Radio library.",
        public_access: true,
        collaborative: false
      )
      playlist.save!
      playlist
    end

    def seed_track!(row, owner)
      source_url = row["source_url"].to_s.strip
      relative_path = row["local_path"].to_s.strip
      return [ nil, false ] if source_url.empty? || relative_path.empty?

      path = Rails.root.join(relative_path)
      return [ nil, false ] unless path.file?

      track = Playlist::Track.find_or_initialize_by(source_url: source_url)
      track.assign_attributes(
        title: row["title"].to_s.presence || "Untitled",
        artist: row["artist"].to_s.presence || "Unknown artist",
        duration_seconds: row["duration_seconds"].to_i.positive? ? row["duration_seconds"].to_i : nil,
        source_type: "upload"
      )
      track.privacy = "public" if track.has_attribute?(:privacy)
      track.genre = "radio" if track.has_attribute?(:genre)
      track.user = owner if track.new_record? && track.respond_to?(:user=)
      track.save!

      return [ track, false ] if track.audio_file.attached?

      File.open(path, "rb") do |io|
        track.audio_file.attach(
          io: io,
          filename: path.basename.to_s,
          content_type: audio_content_type(path)
        )
      end
      [ track, true ]
    end

    def audio_content_type(path)
      path.extname.downcase == ".mp3" ? "audio/mpeg" : "application/octet-stream"
    end
  end
end
