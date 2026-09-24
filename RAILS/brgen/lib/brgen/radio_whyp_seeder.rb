# frozen_string_literal: true

require "yaml"

module Brgen
  class RadioWhypSeeder
    DEFAULT_CITIES = %w[brgen.no lsangeles.com].freeze

    Result = Data.define(:cities, :tracks, :playlists)

    def initialize(manifest_path:, cities: DEFAULT_CITIES)
      @manifest_path = Pathname.new(manifest_path)
      @cities = Array(cities).map(&:to_s).reject(&:blank?).uniq
    end

    def call
      manifest = load_manifest
      rows = manifest.fetch("tracks")
      tracks = rows.map { |row| upsert_track(row) }

      playlists = @cities.map do |domain|
        city = City.find_by(domain: domain) or abort "radio: city missing: #{domain}"
        ActsAsTenant.with_tenant(city) { seed_city(city, tracks) }
      end

      Result.new(@cities, tracks.size, playlists.size)
    end

    private

    attr_reader :manifest_path, :cities

    def load_manifest
      abort "radio: manifest missing: #{manifest_path}" unless manifest_path.file?

      YAML.safe_load_file(manifest_path, permitted_classes: [], aliases: true).tap do |data|
        abort "radio: manifest has no tracks" unless data.is_a?(Hash) && Array(data["tracks"]).any?
      end
    end

    def upsert_track(row)
      source_url = row.fetch("source_url")
      track = Playlist::Track.find_or_initialize_by(source_url: source_url)
      track.assign_attributes(
        title: row.fetch("title"),
        artist: row.fetch("artist"),
        source_type: row.fetch("source_type", "whyp"),
        duration_seconds: row["duration_seconds"],
        privacy: "public",
        genre: "radio"
      )
      track.save!

      attach_media!(track, row, :audio, "audio/mpeg")
      attach_media!(track, row, :artwork, artwork_content_type(row))
      track
    end

    def attach_media!(track, row, field, fallback_content_type)
      attachment = track.public_send("#{field}_file")
      relative = row[field.to_s].presence
      return unless relative

      path = Rails.root.join(relative)
      abort "radio: media missing: #{path}" unless path.file? && path.size.positive?
      return if attachment.attached? && attachment.blob.byte_size == path.size

      attachment.attach(
        io: File.open(path, "rb"),
        filename: path.basename.to_s,
        content_type: Rack::Mime.mime_type(path.extname).presence || fallback_content_type
      )
    end

    def artwork_content_type(row)
      path = row["artwork"].presence
      return "image/jpeg" unless path

      Rack::Mime.mime_type(File.extname(path)).presence || "image/jpeg"
    end

    def seed_city(city, tracks)
      owner = radio_owner(city)
      name = "Radio #{city.name}"

      playlist = Playlist::Playlist.find_or_initialize_by(city: city, name: name)
      playlist.assign_attributes(
        user: owner,
        public_access: true,
        collaborative: false
      )
      playlist.save!

      tracks.each { |track| playlist.add_track!(track, user: owner) }
      playlist.update_column(:tracks_count, playlist.tracks.count) if playlist.tracks_count != playlist.tracks.count
      playlist
    end

    def radio_owner(city)
      email = "radio@#{city.domain}"
      ActsAsTenant.without_tenant do
        User.find_or_create_by!(email_address: email) do |user|
          user.username = "radio_#{city.domain.tr(".", "_")}"
          user.password = user.password_confirmation = SecureRandom.base58(32)
          user.city = city
          user.display_name = "Radio #{city.name}" if user.has_attribute?(:display_name)
        end
      end
    end
  end
end
