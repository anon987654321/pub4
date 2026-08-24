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

      # One candidate now, not four. The three fallbacks pointed into
      # studio/radio-bergen, which no longer exists — brgen serves this playlist,
      # so the manifest lives in brgen's own config where the first candidate
      # always looked. In development that path resolves directly; in production
      # it is the same path, so there is nothing left to fall back to.
      def manifest_candidates
        [ rails_root.join("config/radio_bergen/tracks.yml") ]
      end

      def lessons_candidates
        [
          rails_root.join("config/radio_bergen/archive_lessons.yml"),
          rails_root.join("../../../MASTER/data/lessons/pub_archive_restore.yml").expand_path,
          Pub4::DeployPaths.repo_join("MASTER/data/lessons/pub_archive_restore.yml"),
          Pathname.new("#{Pub4::DeployPaths::DEFAULT_REPO}/MASTER/data/lessons/pub_archive_restore.yml")
        ]
      end

      # All four candidates named a subsystem that no longer exists: 41b20306d
      # removed studio/radio-bergen ("brgen's playlist replaced what it served"),
      # and the surviving three paths were lowercase `studio/` after 2d4551597
      # renamed the directory to STUDIO. So sonic_learnings returned {} on every
      # call, and radio_bergen_study_test.rb skipped itself rather than failing.
      # The learnings live in the dilla engine's own reference file now.
      def sonic_learnings_candidates
        [
          rails_root.join("config/radio_bergen/sonic.yml"),
          rails_root.join("../../../STUDIO/dilla/reference_sonic.yml").expand_path,
          Pub4::DeployPaths.repo_join("STUDIO/dilla/reference_sonic.yml"),
          Pathname.new("#{Pub4::DeployPaths::DEFAULT_REPO}/STUDIO/dilla/reference_sonic.yml")
        ]
      end

      def sonic_learnings_path
        Pub4::DeployPaths.first_file(sonic_learnings_candidates)
      end

      def sonic_learnings
        path = sonic_learnings_path
        return {} unless path

        YAML.safe_load(File.read(path), permitted_classes: [], aliases: true) || {}
      end

      def stream_rotation_weights
        weights = sonic_learnings["stream_rotation_weights"]
        return {} unless weights.is_a?(Hash)

        weights.transform_keys(&:to_s)
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
          # These two are rendered to the visitor on the playlist surface, so
          # they name paths that exist. studio/radio-bergen/ was removed in
          # 41b20306d; the manifest moved into this app and the learnings into
          # the dilla engine.
          "manifest: RAILS/brgen/config/radio_bergen/tracks.yml",
          "learnings: STUDIO/dilla/reference_sonic.yml (ruby scripts/radio_bergen_study.rb)",
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
