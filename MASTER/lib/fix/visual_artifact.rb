# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

module Master
  module Fix
    # Durable, bounded browser evidence for a visual pass. Source and Git remain
    # authoritative; this is only the rendered artifact a human can inspect after
    # the browser session is gone.
    class VisualArtifact
      MAX_FILES = 72
      MAX_BYTES = 24 * 1024 * 1024

      def initialize(root:)
        @root = root
      end

      # Writes the pass's evidence and tells the bus where it went.
      def keep(target:, pass:, captures:, image:, bus:)
        write(target:, pass:, captures:, contact_sheet: image[:path]).tap do |artifact|
          bus&.publish("fix_loop:visual_artifact", pass:, dir: artifact&.dig(:dir), files: artifact&.dig(:files))
        end
      end

      def write(target:, pass:, captures:, contact_sheet:)
        run_id = Time.now.utc.strftime("%Y%m%dT%H%M%S%6N")
        dir = File.join(@root, "MASTER", ".master", "visual_artifacts", run_id)
        FileUtils.mkdir_p(dir)

        entries = []
        add(entries, contact_sheet, dir, label: "contact-sheet", surface: "all", kind: "contact_sheet")
        Array(captures).each { |capture| add_capture(entries, capture, dir) }
        manifest_path = write_manifest(dir, target:, pass:, entries:)
        FileUtils.ln_sf(File.basename(dir), File.join(File.dirname(dir), "latest"))
        { dir:, manifest: manifest_path, files: entries.size }
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "fix.visual_artifact", event_bus: nil)
        nil
      end

      private

      # The ghost stack's layers, each copied under the label a person reads it by.
      GHOST_LAYERS = {
        screenshot: "ghost",
        diff: "difference",
        geometry: "geometry",
        grid: "grid",
        focus: "focus",
        squint: "squint",
      }.freeze

      def add_capture(entries, capture, dir)
        surface = capture[:surface].id.to_s
        add(entries, capture[:screenshot], dir, label: surface, surface:, kind: "surface")
        Array(capture[:journeys]).each_with_index do |journey, index|
          add(entries, journey["screenshot"], dir,
              label: "#{surface}-journey-#{index + 1}-#{journey["kind"]}", surface:, kind: "journey")
        end
        ghost = capture[:visual_evidence]&.dig(:ghost)
        return unless ghost

        GHOST_LAYERS.each do |key, label|
          add(entries, ghost[key], dir, label: "#{surface}-#{label}", surface:, kind: label) if ghost[key]
        end
      end

      def write_manifest(dir, target:, pass:, entries:)
        manifest = {
          "schema" => 1,
          "created_at" => Time.now.utc.iso8601,
          "target" => target.to_s,
          "pass" => pass.to_i,
          "files" => entries,
        }
        File.join(dir, "manifest.json").tap { |path| File.write(path, JSON.pretty_generate(manifest) + "\n") }
      end

      def add(entries, source, dir, label:, surface:, kind:)
        return if entries.size >= MAX_FILES
        return unless source && File.file?(source)

        used = entries.sum { |row| row["bytes"].to_i }
        bytes = File.size(source)
        return if used + bytes > MAX_BYTES

        extension = File.extname(source)
        name = "#{format("%03d", entries.size + 1)}-#{safe(label)}#{extension}"
        destination = File.join(dir, name)
        FileUtils.cp(source, destination)
        entries << {
          "file" => name,
          "bytes" => bytes,
          "surface" => surface.to_s,
          "kind" => kind.to_s,
          "label" => label.to_s,
        }
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "fix.visual_artifact.copy", path: source)
      end

      def safe(value) = value.to_s.gsub(/[^a-zA-Z0-9._-]+/, "_")[0, 96]
    end
  end
end
