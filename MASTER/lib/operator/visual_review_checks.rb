# frozen_string_literal: true

require "fileutils"
require "json"

module Operator
  # Check results for one capture, read-only: the quality metrics, the worsening
  # against the stored per-surface baseline, and the chrome drift budget. The
  # fix loop's recorders (VisualQualityChecks.record/judge, VisualDriftBudget
  # .check) write baselines and parked renders, so the review calls only their
  # pure halves and never a writer.
  module VisualReviewChecks
    module_function

    # A table row for the page: title, metrics, problems, image links.
    def row(capture, root:, dir:)
      surface = capture[:surface]
      payload = capture[:payload]
      state = payload.dig("composition", "state") || "resting"
      measured = Master::Fix::VisualQualityChecks.measure(surface, payload)
      {
        title: "#{surface.id} / #{state}", surface: surface.id, state:,
        screenshot: relative(capture[:screenshot], dir),
        metrics: measured["metrics"],
        problems: problems(measured, surface, state, root:) + drift(surface, payload, root:),
        extras: extras(capture, dir),
      }
    end

    def problems(measured, surface, state, root:)
      found = measured["offenders"].filter_map do |name, keys|
        "#{name}: #{keys.size} (#{keys.first(3).join(", ")})" unless keys.empty?
      end
      found << "layout_shift: #{measured["metrics"]["layout_shift"]}" if measured["metrics"]["layout_shift"].to_f > Master::Fix::VisualQualityChecks::SHIFT_GOOD
      return found unless state == "resting"

      base = Master::Fix::VisualQualityChecks.load(root, surface)
      base ? found + Master::Fix::VisualQualityChecks.worse(base, measured).map { |line| "worse than baseline, #{line}" } : found
    end

    # Chrome boxes that moved beyond tolerance against the blessed baseline.
    def drift(surface, payload, root:)
      return [] unless payload.dig("composition", "state").to_s.then { |s| s.empty? || s == "resting" }

      path = Master::Fix::VisualDriftBudget.file(root, surface.id, "baseline")
      return [] unless File.file?(path)

      base = JSON.parse(File.read(path))
      now = Master::Fix::VisualDriftBudget.chrome_rects(payload)
      (base.keys & now.keys).flat_map { |key| Master::Fix::VisualDriftBudget.deltas(key, base[key], now[key], []) }
                            .map { |line| "chrome drift #{line}" }
    rescue JSON::ParserError => e
      # A baseline that cannot be read measured nothing; saying so keeps the row from reading clean.
      ["chrome drift baseline unreadable, #{e.message.lines.first.to_s.strip[0, 120]}"]
    end

    # Every picture a capture owns besides its main screenshot.
    def extras(capture, dir)
      paths = []
      evidence = capture[:visual_evidence] || {}
      (evidence[:ghost] || {}).each { |name, value| paths << [name.to_s, value] if value.is_a?(String) }
      Array(capture[:journeys]).each { |j| paths << ["journey #{j["kind"]}:#{j["label"]}", j["screenshot"]] }
      paths.filter_map do |label, path|
        rel = relative(path, dir)
        { label:, path: rel } if rel
      end
    end

    def relative(path, dir)
      return unless path.is_a?(String) && File.file?(path)

      path.start_with?("#{dir}/") ? path.delete_prefix("#{dir}/") : path
    end
  end
end
