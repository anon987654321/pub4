# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "../master"
require_relative "../result"
require_relative "visual_conformance"
require_relative "visual_drift_budget"
require_relative "visual_focus_order"
require_relative "visual_i18n"
require_relative "layout_score_store"

module Master
  module Fix
    # Measured quality of a rendered surface, computed from the geometry payload
    # a capture already holds. A visual fix is accepted only when no metric is
    # worse than the surface's stored baseline; improvements move the baseline
    # forward, regressions leave it where it was.
    #
    # Focus order is read from the recorded Tab sequence against reading order
    # (document order when none was recorded), and the layout shift figure is a
    # proxy: moved area times distance against the baseline render, because one capture cannot observe a shift in time.
    module VisualQualityChecks
      TAP_MIN_PX = 44
      MOBILE_MAX_VW = 600
      AA_TEXT = 4.5
      AA_LARGE = 3.0
      SHIFT_GOOD = 0.1
      MOVE_TOLERANCE_PX = 0.5
      KEEP = 50

      module_function

      def dir(root) = File.join(Master.master_root(root:), ".master", "visual_quality")

      def slug(surface) = surface.id.to_s.gsub(/[^a-zA-Z0-9._-]+/, "_")

      def path(root, surface) = File.join(dir(root), "#{slug(surface)}.json")

      # Metrics for one payload: counts of offenders, each with the keys that offend.
      def measure(surface, payload, baseline_rects: nil)
        els = Array(payload["elements"]).select { |e| e["visible"] != false }
        offenders = {
          "contrast" => els.select { |e| contrast_fail?(e) },
          "tap_target" => tap_fails(els, payload),
          "focus_order" => VisualFocusOrder.inversions(els, payload),
          "overflow" => overflow(payload),
          "i18n" => els.select { |e| i18n_broken?(e) } + VisualI18n.rows(payload),
          "directives" => VisualConformance.check_payload(surface, payload),
        }
        metrics = offenders.transform_values(&:size)
        metrics["layout_shift"] = shift(els, payload, baseline_rects)
        { "metrics" => metrics, "offenders" => offenders.transform_values { |rows| rows.map { |r| label(r) }.first(KEEP) },
          "rects" => rects(els) }
      end

      def label(row) = row.is_a?(Hash) ? (row["key"] || row["sel"]).to_s : row.selector.to_s

      def rects(els) = els.filter_map { |e| (box = e["frect"] || e["rect"]).is_a?(Hash) && [e["key"], box.values_at("x", "y", "w", "h")] }.to_h

      def luminance(hex)
        r, g, b = hex.delete("#").scan(/../).map { |c| c.to_i(16) / 255.0 }
        lin = [r, g, b].map { |v| v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055)**2.4 }
        (0.2126 * lin[0]) + (0.7152 * lin[1]) + (0.0722 * lin[2])
      end

      def ratio(fg, bg)
        hi, lo = [luminance(fg), luminance(bg)].sort.reverse
        (hi + 0.05) / (lo + 0.05)
      end

      def contrast_fail?(el)
        return false if el["text"].to_s.empty? || !el["color"] || !el["bg"]

        large = el["font_size"].to_f >= 24 || (el["font_size"].to_f >= 18.66 && el["font_weight"].to_i >= 700)
        ratio(el["color"], el["bg"]) < (large ? AA_LARGE : AA_TEXT)
      end

      def tap_fails(els, payload)
        return [] unless payload["vw"].to_f <= MOBILE_MAX_VW

        els.select do |e|
          e["interactive"] && !e["inline_in_text"] && e["onscreen"] != false && e["rect"] &&
            (e["rect"]["w"].to_f < TAP_MIN_PX || e["rect"]["h"].to_f < TAP_MIN_PX)
        end
      end

      def overflow(payload)
        rows = Array(payload["overflow"]).dup
        rows << { "sel" => "document" } if payload["scroll_width"].to_f > payload["client_width"].to_f + 1
        rows
      end

      def i18n_broken?(el) = VisualI18n.broken?(el["text"], el["key"])

      # Sum of (moved area / viewport area) * (distance / viewport height) over
      # the largest moved boxes, skipping any box nested inside one counted.
      def shift(els, payload, before)
        return 0.0 unless before

        area = payload["vw"].to_f * payload["vh"].to_f
        return 0.0 if area <= 0

        counted = []
        total = 0.0
        moved(els, before).sort_by { |_, old, now, _| -(now[2] * now[3]) }.each do |_, old, now, dist|
          next if counted.any? { |o| old[0] >= o[0] && old[1] >= o[1] && old[0] + old[2] <= o[0] + o[2] && old[1] + old[3] <= o[1] + o[3] }

          counted << old
          total += (now[2] * now[3] / area) * (dist / payload["vh"].to_f)
        end
        total.round(4)
      end

      def moved(els, before)
        els.filter_map do |e|
          old = before[e["key"]]
          now = (e["frect"] || e["rect"])&.values_at("x", "y", "w", "h")
          next unless old && now

          dist = [(now[0] - old[0]).abs, (now[1] - old[1]).abs].max
          [e["key"], old, now, dist] if dist > MOVE_TOLERANCE_PX
        end
      end

      def worse(base, cur, allow_layout_change: false)
        base["metrics"].filter_map do |name, was|
          now = cur["metrics"][name].to_f
          next if allow_layout_change && name == "layout_shift"
          next if name == "layout_shift" ? now <= [was.to_f, SHIFT_GOOD].max : now <= was.to_f

          fresh = Array(cur["offenders"][name]) - Array(base["offenders"][name])
          "#{name} #{was}->#{now}#{fresh.empty? ? "" : " (#{fresh.first(3).join(", ")})"}"
        end
      end

      def load(root, surface)
        JSON.parse(File.read(path(root, surface)))
      rescue Errno::ENOENT, JSON::ParserError
        nil
      end

      def save(root, surface, entry)
        FileUtils.mkdir_p(dir(root))
        File.write(path(root, surface), JSON.pretty_generate(entry))
      end

      # Called before a visual fix: stores each resting surface's measurements as
      # the state the fix must not worsen, and seeds the drift baseline.
      def record(captures, root:)
        rows = Array(captures).select { |c| c.dig(:payload, "composition", "state") == "resting" }
        rows.each do |c|
          save(root, c[:surface], measure(c[:surface], c[:payload]))
          VisualDriftBudget.seed(c[:surface], c[:payload], root:)
          LayoutScoreStore.seed(c[:surface], c[:payload], root:)
        end
        log("baseline: #{rows.size} surface(s) recorded")
      end

      # Called after a visual fix with the re-measured [surface, payload] pairs.
      # `prior` is the verdict already reached (snapshot custody); a failing
      # prior stands. Otherwise any worsened metric or unanchored chrome drift
      # rejects the fix.
      def judge(measured, root:, prior:, anchors: [], allow_layout_change: false)
        return prior unless prior.ok?

        problems = []
        accepted = []
        measured.each do |surface, payload|
          base = load(root, surface)
          cur = measure(surface, payload, baseline_rects: base && base["rects"])
          bad = base ? worse(base, cur, allow_layout_change:) : []
          drift = VisualDriftBudget.check(surface, payload, root:, anchors:)
          bad += LayoutScoreStore.judge(surface, payload, root:)
          problems << "#{surface.id}: #{bad.join("; ")}" unless bad.empty?
          problems << "#{surface.id}: chrome drift #{drift.first(3).join(", ")} (bin/operator visual approve #{surface.id})" unless drift.empty?
          accepted << [surface, cur]
        end
        accepted.each { |surface, cur| save(root, surface, cur) } if problems.empty?
        LayoutScoreStore.settle(measured, root:) if problems.empty?
        log("verdict: #{problems.empty? ? "no metric worse" : "regression"} over #{measured.size} surface(s)")
        return prior if problems.empty?

        Result.err("visual quality: regression — #{problems.join(" / ")}", category: :policy)
      end

      def log(message)
        Master::Trace::Dmesg.status("visual0", message)
      rescue StandardError
        nil
      end
    end
  end
end
