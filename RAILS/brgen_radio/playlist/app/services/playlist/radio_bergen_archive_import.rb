# frozen_string_literal: true

require "digest/md5"
require "pathname"

module Playlist
  class RadioBergenArchiveImport
    Result = Struct.new(:playlist, :tracks, :new_audio_attachments, :new_playlist_entries, keyword_init: true)
    class RightsNotConfirmed < StandardError; end
    class InvalidArchive < StandardError; end
    class TenantNotSelected < StandardError; end
    class OwnerTenantMismatch < StandardError; end

    SAFE_AUDIO_FILENAME = /\A[a-z0-9_][a-z0-9_.-]*\.mp3\z/i
    SOURCE_REVISION = "ad05242c97fff1b01450434974aad628d7de8628"

    def initialize(owner:, city:, archive_root:, rights_confirmed: false)
      @owner = owner
      @city = city
      @archive_root = Pathname.new(archive_root).expand_path
      @rights_confirmed = rights_confirmed
    end

    def call
      raise RightsNotConfirmed, "Confirm distribution rights for every recording before importing" unless @rights_confirmed
      raise InvalidArchive, "Owner must be a saved user" unless owner&.persisted?
      unless city&.persisted? && city.domain == "brgen.no"
        raise TenantNotSelected, "Select the saved brgen.no city tenant before importing"
      end
      raise OwnerTenantMismatch, "Owner must belong to the brgen.no city tenant" unless owner.city_id == city.id

      ActsAsTenant.with_tenant(city) do
        entries = Brgen::RadioBergenManifest.curated_tracks
        raise InvalidArchive, "Curated manifest is empty" if entries.empty?

        prepared = entries.map do |entry|
          filename = entry["source_file"].to_s
          unless SAFE_AUDIO_FILENAME.match?(filename) && Pathname.new(filename).basename.to_s == filename
            raise InvalidArchive, "Unsafe archive filename: #{filename.inspect}"
          end
          path = archive_root.join(filename)
          raise InvalidArchive, "Missing or empty archive audio file: #{path}" unless path.file? && path.size.positive?
          [entry, path, Digest::MD5.file(path).base64digest]
        end

        # Preflight attached sources before writing; never overwrite a changed
        # audio file merely because the archive import is rerun.
        prepared.each do |entry, _path, checksum|
          existing = find_track(entry)
          next unless existing&.audio_file&.attached?
          next if existing.audio_file.blob.checksum == checksum
          raise InvalidArchive, "Existing audio differs from archive for #{entry['artist']} — #{entry['title']}"
        end

        playlist = nil
        imported_tracks = []
        attached_count = 0
        added_count = 0

        ActiveRecord::Base.transaction do
          playlist = ::Playlist::Playlist.find_or_initialize_by(
            user: owner,
            name: Brgen::RadioBergenManifest.curated_playlist_name
          )
          playlist.assign_attributes(
            description: Brgen::RadioBergenManifest.curated_description,
            public_access: true,
            collaborative: false
          )
          playlist.save!

          prepared.each do |entry, path, _checksum|
            track = find_track(entry) || ::Playlist::Track.new
            track.assign_attributes(
              user: owner,
              title: entry.fetch("title"),
              artist: entry.fetch("artist"),
              album: Brgen::RadioBergenManifest.curated_album,
              source_type: "upload",
              source_url: "https://github.com/anon987654321/pub2/blob/#{SOURCE_REVISION}/#{entry.fetch('source_file')}",
              privacy: "public"
            )
            track.save!
            unless track.audio_file.attached?
              File.open(path, "rb") do |file|
                track.audio_file.attach(io: file, filename: path.basename.to_s, content_type: "audio/mpeg")
              end
              track.save!
              attached_count += 1
            end
            unless playlist.playlist_tracks.exists?(playlist_track_id: track.id)
              playlist.add_track!(track, user: owner)
              added_count += 1
            end
            imported_tracks << track
          end
        end

        Result.new(playlist: playlist, tracks: imported_tracks,
                   new_audio_attachments: attached_count, new_playlist_entries: added_count)
      end
    end
    private

    attr_reader :owner, :city, :archive_root

    def find_track(entry)
      ::Playlist::Track.find_by(
        user: owner,
        album: Brgen::RadioBergenManifest.curated_album,
        title: entry.fetch("title"),
        artist: entry.fetch("artist")
      )
    end
  end
end
