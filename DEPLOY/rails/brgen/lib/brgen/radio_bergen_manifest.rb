# frozen_string_literal: true

module Brgen
  # Shared Radio Bergen manifest loader — pub2 index.html archaeology split into data + Rails.
  class RadioBergenManifest
    MANIFEST_PATH = Rails.root.join("../../..", "MASTER/tools/audio/radio_bergen_tracks.yml").expand_path
    LESSONS_PATH = Rails.root.join("../../..", "MASTER/data/lessons/pub_archive_restore.yml").expand_path

    class << self
      def load
        return {} unless MANIFEST_PATH.exist?

        YAML.safe_load(MANIFEST_PATH.read, permitted_classes: [], aliases: true) || {}
      end

      def youtube_tracks
        Array(load.dig("external_reference", "youtube")).filter_map do |row|
          id = row["id"].presence
          next unless id

          {
            title: row["title"].to_s,
            id: id,
            artist: row["artist"].presence || "Brgen"
          }
        end
      end

      def archaeology_lines
        manifest = load
        meta = manifest["meta"] || {}
        pub2_head = lessons_pub2_head
        local_count = Array(manifest["local_mp3"]).size
        youtube_count = youtube_tracks.size

        [
          "$ git dig --follow pub4/index.html",
          "object: pub2 monolithic index.html → playlist.brgen.no warp tunnel",
          "archive: #{meta['source_archive'] || 'anon987654321/pub2'} @ #{pub2_head}",
          "manifest: MASTER/tools/audio/radio_bergen_tracks.yml",
          "lesson: do_not_restore monolithic index.html — manifest + Rails vertical instead",
          "excavated: #{local_count} local_mp3 metadata rows · #{youtube_count} youtube references",
          "policy: #{manifest.dig('external_reference', 'policy') || 'reference_only_until_rights_review'}",
          "surface: radio.brgen.no — tap to boot tunnel (pub4 matrix index.html lineage)"
        ]
      end

      def lessons_pub2_head
        return "ad05242c97ff" unless LESSONS_PATH.exist?

        data = YAML.safe_load(LESSONS_PATH.read, permitted_classes: [], aliases: true) || {}
        data.dig("pub2", "head") || "ad05242c97ff"
      end
    end
  end
end