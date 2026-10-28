# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "../master"
require "time"
require_relative "layout_score"

module Master
  module Fix
    # History, baseline and verdict for LayoutScore. The baseline is the best
    # score a surface has held; a visual fix whose score falls more than the
    # tolerance below it is a regression, the same contract as VisualQualityChecks.
    # History is a trail under MASTER/.master/layout_score/ and never an input.
    module LayoutScoreStore
      KEEP = 50
      TOLERANCE = Float(ENV.fetch("MASTER_LAYOUT_SCORE_TOLERANCE", "2.0"))

      module_function

      def dir(root) = File.join(Master.master_root(root:), ".master", "layout_score")

      def path(root, surface) = File.join(dir(root), "#{surface.id.to_s.gsub(/[^a-zA-Z0-9._-]+/, "_")}.json")

      def tokens(root) = (@tokens ||= {})[root] ||= LayoutScoreTokens.load(root)

      def measure(root, payload) = LayoutScore.compute(payload, tokens: tokens(root))

      def load(root, surface)
        JSON.parse(File.read(path(root, surface)))
      rescue Errno::ENOENT, JSON::ParserError
        nil
      end

      # A score version changes when its measurement semantics change. Old
      # scores remain in history but cannot veto a render scored by new rules.
      def baseline(root, surface)
        row = load(root, surface)&.dig("baseline")
        row["score"] if row.is_a?(Hash) && row["version"] == LayoutScore::VERSION
      end

      # Stores the resting score as the state a fix must not worsen.
      def seed(surface, payload, root:)
        write(root, surface, measure(root, payload), advance: true)
      end

      # Problems (strings) for one re-measured surface; empty when the score
      # held within tolerance or there was no baseline to hold it to.
      def judge(surface, payload, root:)
        base = baseline(root, surface)
        return [] unless base

        now = measure(root, payload)
        announce(surface, now, base)
        return [] if now.score >= base - TOLERANCE

        ["layout score #{base} -> #{now.score} (tolerance #{TOLERANCE})"]
      end

      # Called once every check has passed: the new render becomes history, and
      # the baseline only ever moves up.
      def settle(measured, root:)
        measured.each { |surface, payload| write(root, surface, measure(root, payload), advance: true) }
      end

      def write(root, surface, result, advance:)
        entry = load(root, surface) || { "history" => [] }
        row = { "version" => LayoutScore::VERSION, "at" => Time.now.utc.iso8601,
                "score" => result.score, "subs" => round(result.subs), "facts" => result.facts }
        entry["history"] = (entry["history"] << row).last(KEEP)
        baseline = entry["baseline"]
        compatible = baseline.is_a?(Hash) && baseline["version"] == LayoutScore::VERSION
        entry["baseline"] = row if advance && (!compatible || row["score"] >= baseline["score"].to_f)
        FileUtils.mkdir_p(dir(root))
        File.write(path(root, surface), JSON.pretty_generate(entry))
      end

      def round(subs) = subs.transform_values { |v| v&.round(2) }

      # The one line a reader sees, and the same text the critique is shown.
      def line(surface, result, base)
        delta = base ? format(" (%+.1f)", result.score - base) : ""
        s = result.subs
        "#{surface.id} #{result.score}#{delta} edges #{result.facts["edges"]} grid #{fmt(s["grid"])} " \
          "scale #{fmt(s["scale"])} measure #{result.facts["outliers"]} outliers"
      end

      def fmt(value) = value ? format("%.2f", value) : "n/a"

      def announce(surface, result, base)
        Master::Trace::Dmesg.status("score0", line(surface, result, base))
      rescue StandardError
        nil
      end

      # Evidence row for the critique: the score, its weakest parts, in words.
      def row(capture, root:)
        return unless capture.dig(:payload, "composition", "state") == "resting"

        surface = capture[:surface]
        result = measure(root, capture[:payload])
        base = baseline(root, surface)
        announce(surface, result, base)
        weak = result.subs.compact.sort_by { |_, v| v }.first(3).map { |k, v| "#{k} #{fmt(v)}" }
        "layout score #{line(surface, result, base)}; weakest: #{weak.join(", ")}"
      rescue StandardError
        nil
      end
    end
  end
end
