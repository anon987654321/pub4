# frozen_string_literal: true

require "pub4/deploy_paths"

module Brgen
  # Shared Radio Bergen manifest loader — pub2 index.html archaeology split into data + Rails.
  class RadioBergenManifest
    class << self
      def manifest_path
        Pub4::DeployPaths.first_file(manifest_candidates)
      end

      def lessons_path
        Pub4::DeployPaths.first_file(lessons_candidates)
      end

      def manifest_candidates
        [
          rails_root.join("config/radio_bergen/tracks.yml"),
          rails_root.join("../../../MASTER/tools/audio/radio_bergen_tracks.yml").expand_path,
          Pub4::DeployPaths.repo_join("MASTER/tools/audio/radio_bergen_tracks.yml"),
          Pathname.new("#{Pub4::DeployPaths::DEFAULT_REPO}/MASTER/tools/audio/radio_bergen_tracks.yml")
        ]
      end

      def lessons_candidates
        [
          rails_root.join("config/radio_bergen/archive_lessons.yml"),
          rails_root.join("../../../MASTER/data/lessons/pub_archive_restore.yml").expand_path,
          Pub4::DeployPaths.repo_join("MASTER/data/lessons/pub_archive_restore.yml"),
          Pathname.new("#{Pub4::DeployPaths::DEFAULT_REPO}/MASTER/data/lessons/pub_archive_restore.yml")
        ]
      end

      def rails_root
        Pathname.new(Rails.root)
      end

      def load
        path = manifest_path
        return {} unless path

        YAML.safe_load(File.read(path), permitted_classes: [], aliases: true) || {}
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
        path = lessons_path
        return "ad05242c97ff" unless path

        data = YAML.safe_load(File.read(path), permitted_classes: [], aliases: true) || {}
        data.dig("pub2", "head") || "ad05242c97ff"
      end
    end
  end
end