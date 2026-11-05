# frozen_string_literal: true

module Brgen
  # Radio Bergen's demo playlist: the tracks Radio Bergen's manifest lists as
  # YouTube references, owned by the Live account and kept in step with the
  # manifest. Included by BergenDemoSeeder, whose @city and @users_by_username
  # these read; private like the seeder's other steps.
  module BergenDemoRadio
    private

    def seed_playlists
      owner = @users_by_username.fetch("live_bergenlive")
      # Spelled in full: the constant is BergenDemoData's, and this module is not
      # inside it.
      name = BergenDemoData::RADIO_BERGEN_PLAYLIST
      playlist = Playlist::Playlist.find_or_initialize_by(city: @city, name: name, user: owner)
      playlist.assign_attributes(
        description: "Beat-referanser fra Radio Bergen-manifestet. Nattbuss, tunnel og regnby.",
        public_access: true,
        collaborative: false,
        # Seed fixtures must not invent playback. Preserve an existing event-backed count.
        plays_count: playlist.plays_count.to_i
      )
      playlist.save!

      return if playlist.tracks.count >= radio_bergen_manifest_tracks.size

      radio_bergen_manifest_tracks.each do |row|
        track = find_or_create_radio_track!(row, owner: owner)
        playlist.add_track!(track, user: owner)
      end
      playlist.update_column(:tracks_count, playlist.tracks.count) if playlist.tracks_count != playlist.tracks.count
    end

    def radio_bergen_manifest_tracks
      @radio_bergen_manifest_tracks ||= begin
        manifest = load_radio_bergen_manifest
        Array(manifest.dig("external_reference", "youtube")).map do |row|
          {
            artist: row["artist"],
            title: row["title"],
            source_type: "youtube",
            source_url: "https://www.youtube.com/watch?v=#{row['id']}"
          }
        end
      end
    end

    def load_radio_bergen_manifest
      RadioBergenManifest.load
    end

    def find_or_create_radio_track!(row, owner:)
      Playlist::Track.find_or_create_by!(
        title: row[:title],
        artist: row[:artist],
        source_type: row[:source_type],
        source_url: row[:source_url]
      ) do |track|
        track.user = owner if track.has_attribute?(:user_id)
        track.privacy = "public"
        track.duration_seconds = rand(150..320)
        track.genre = row[:source_type] == "direct" ? "bergen" : "beats"
        # "Utvalgt spor" renders the artwork square above the title; a track
        # without one shows a bare grey box where the media station's focal
        # field should be. Catalogue cover, deterministic per title.
        Brgen::DemoMedia.attach_catalog!(track, :artwork, seed: "radio-track-#{row[:title].parameterize[0, 32]}")
      end
    end
  end
end
