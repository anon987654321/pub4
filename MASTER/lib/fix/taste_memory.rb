# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "time"
require_relative "visual_cross_page_overlay"
require_relative "repair_outcomes"

module Master
  module Fix
    # What the operator approved and rejected in rendered layouts, kept as
    # compact descriptors so the next critique and fix prompt can say "approved
    # looks like" and "rejected looks like". Only the operator writes a verdict
    # (`bin/operator visual taste approve|reject`, and `visual approve`); the
    # loop never does. Entries decay with a half-life and the file keeps at most
    # MAX_ENTRIES, so an old taste fades and the file stays small.
    class TasteMemory
      PATH = File.join(".master", "taste.json")
      HALF_LIFE_DAYS = 45.0
      MAX_ENTRIES = 80
      MIN_WEIGHT = 0.1
      PER_VERDICT = 3
      SUMMARY_BYTES = 800
      MAX_TERMS = 8
      VERDICTS = %w[approved rejected].freeze
      LOCK = Mutex.new

      def initialize(root:, clock: -> { Time.now })
        root = File.expand_path(root)
        @root = File.basename(root) == "MASTER" ? root : File.join(root, "MASTER")
        @file = File.join(@root, PATH)
        @clock = clock
      end

      # surface is "app/label/viewport"; changes is { selectors: [], properties: [] };
      # scores is the layout score's sub-scores when the caller has them.
      def record(surface:, verdict:, note: nil, changes: {}, scores: {})
        raise ArgumentError, "verdict must be one of #{VERDICTS.join(", ")}" unless VERDICTS.include?(verdict.to_s)

        entry = descriptor(surface, verdict.to_s, note, changes, scores)
        LOCK.synchronize do
          data = load
          data["entries"] << entry
          data["entries"] = trim(data["entries"])
          save(data)
        end
        entry
      end

      # An operator rejection also teaches RepairOutcomes that this class of
      # visual fix did not please, so the "avoid" line there fires too.
      def reject(surface:, note: nil, changes: {}, scores: {})
        entry = record(surface:, verdict: "rejected", note:, changes:, scores:)
        RepairOutcomes.new(root: @root, clock: @clock).record(
          File.join("RAILS", entry["app"].to_s), ["RENDERED_VISUAL_REFINEMENT"], { rejected: 1 }, pattern: "taste:#{entry["role"]}"
        )
        entry
      end

      # Prompt lines for the entries most relevant to target (a path or surface
      # id); nil when nothing has been judged.
      def summary(target: nil)
        rows = ranked(target)
        return if rows.empty?

        lines = ["taste (operator-judged, decayed; never override it):"]
        VERDICTS.each do |verdict|
          rows.select { |row| row[:entry]["verdict"] == verdict }.first(PER_VERDICT).each do |row|
            lines << "#{verdict == "approved" ? "approved looks like" : "rejected looks like"}: #{describe(row[:entry])}"
          end
        end
        return if lines.size == 1

        lines.join("\n").byteslice(0, SUMMARY_BYTES).scrub("")
      end

      def self.summary(root, target: nil)
        new(root:).summary(target:)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Fix::TasteMemory.summary")
        nil
      end

      # The operator's verdict on a surface, with the css the working tree
      # changed as its descriptor. root is the repository root.
      def self.operator(root:, surface:, verdict:, note: nil)
        diff, = Open3.capture2("git", "-C", root.to_s, "diff", "HEAD", "-U0", "--", "RAILS/*.scss", "RAILS/*.css")
        changes = changes_from_diff(diff)
        memory = new(root:)
        verdict.to_s == "rejected" ? memory.reject(surface:, note:, changes:) : memory.record(surface:, verdict:, note:, changes:)
      end

      # Selectors and properties on the added lines of a unified css diff.
      def self.changes_from_diff(diff)
        added = diff.to_s.lines.grep(/\A\+(?!\+\+)/).map { |line| line.delete_prefix("+").strip }
        selectors = added.filter_map { |line| line[/\A([^{};:]+?)\s*\{/, 1] }
        properties = added.filter_map { |line| line[/\A([a-z-]+)\s*:/, 1] }
        { "selectors" => selectors.uniq.first(MAX_TERMS), "properties" => properties.uniq.first(MAX_TERMS) }
      end

      private

      def descriptor(surface, verdict, note, changes, scores)
        app, label, viewport = surface.to_s.split("/")
        changes = changes.to_h.transform_keys(&:to_s)
        {
          "surface" => surface.to_s, "app" => app.to_s, "viewport" => viewport.to_s,
          "role" => VisualCrossPageOverlay.role_of(label),
          "verdict" => verdict, "note" => note.to_s.strip[0, 240],
          "selectors" => Array(changes["selectors"]).map(&:to_s).first(MAX_TERMS),
          "properties" => Array(changes["properties"]).map(&:to_s).first(MAX_TERMS),
          "scores" => scores.to_h.transform_keys(&:to_s), "at" => @clock.call.to_i
        }
      end

      def ranked(target)
        wanted = target.to_s
        load["entries"].filter_map do |entry|
          weight = 0.5**((@clock.call.to_i - entry["at"].to_i) / 86_400.0 / HALF_LIFE_DAYS)
          next if weight < MIN_WEIGHT

          weight *= 3 if !wanted.empty? && (wanted.include?(entry["app"].to_s) || wanted == entry["surface"])
          { entry:, weight: }
        end.sort_by { |row| -row[:weight] }
      end

      def describe(entry)
        parts = ["#{entry["app"]} #{entry["role"]} (#{entry["viewport"]})"]
        parts << "selectors #{entry["selectors"].join(" ")}" unless entry["selectors"].empty?
        parts << "properties #{entry["properties"].join(" ")}" unless entry["properties"].empty?
        parts << entry["scores"].map { |name, value| "#{name}=#{value}" }.join(" ") unless entry["scores"].empty?
        parts << "\"#{entry["note"]}\"" unless entry["note"].empty?
        parts.join(", ")
      end

      def trim(entries)
        return entries if entries.size <= MAX_ENTRIES

        now = @clock.call.to_i
        entries.sort_by { |entry| -(0.5**((now - entry["at"].to_i) / 86_400.0 / HALF_LIFE_DAYS)) }.first(MAX_ENTRIES)
      end

      def load
        base = { "schema" => 1, "entries" => [] }
        return base unless File.file?(@file)

        base.merge(JSON.parse(File.read(@file)))
      rescue JSON::ParserError
        base
      end

      def save(data)
        FileUtils.mkdir_p(File.dirname(@file))
        File.write(@file, "#{JSON.pretty_generate(data)}\n")
      end
    end
  end
end
