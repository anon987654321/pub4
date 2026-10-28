# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "../master"
require_relative "taste_memory"

module Master
  module Fix
    # Drift budget for shared chrome. The ghost stack keeps recent frames; this
    # keeps one blessed geometry per surface for header, nav and footer boxes and
    # fails a change that moves them by more than the ghost stack's tolerance
    # outside the selectors the fix is anchored to. The baseline is only ever
    # written by `seed` (first sight) and `approve` (an operator command); a
    # drifting render is parked as pending and never promoted by the loop.
    module VisualDriftBudget
      TOLERANCE_PX = 0.5
      CHROME_TAG = /\A(header|nav|footer)(\.|\z)/
      CHROME_ROLE = %w[banner navigation contentinfo].freeze

      module_function

      def dir(root) = File.join(Master.master_root(root:), ".master", "visual_quality", "drift")

      def file(root, id, kind) = File.join(dir(root), "#{id.to_s.gsub(/[^a-zA-Z0-9._-]+/, "_")}.#{kind}.json")

      def chrome?(el)
        el["key"].to_s.split(">").any? { |part| part.match?(CHROME_TAG) } || CHROME_ROLE.include?(el["role"])
      end

      def chrome_rects(payload)
        Array(payload["elements"]).select { |e| e["visible"] != false && chrome?(e) }
          .to_h { |e| [e["key"], (e["frect"] || e["rect"]).values_at("x", "y", "w", "h")] }
      end

      def write(path, rects)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.pretty_generate(rects))
      end

      def seed(surface, payload, root:)
        path = file(root, surface.id, "baseline")
        write(path, chrome_rects(payload)) unless File.file?(path)
      end

      # Rows "key axis+-delta" for chrome boxes that moved beyond tolerance and
      # sit outside every anchor. A moved render is parked for approval.
      def check(surface, payload, root:, anchors: [])
        path = file(root, surface.id, "baseline")
        return [] unless File.file?(path)

        base = JSON.parse(File.read(path))
        now = chrome_rects(payload)
        rows = (base.keys & now.keys).flat_map { |key| deltas(key, base[key], now[key], anchors) }
        pending = file(root, surface.id, "pending")
        rows.empty? ? FileUtils.rm_f(pending) : write(pending, now)
        log("drift #{surface.id}: #{rows.size} chrome move(s) outside anchors") unless rows.empty?
        rows
      rescue JSON::ParserError
        []
      end

      def log(message)
        Master::Trace::Dmesg.status("visual0", message)
      rescue StandardError, NameError
        nil
      end

      def deltas(key, old, new, anchors)
        return [] if anchors.any? { |a| key.include?(a) }

        %w[x y w h].each_with_index.filter_map do |axis, i|
          d = new[i].to_f - old[i].to_f
          "#{key} #{axis}#{d.positive? ? "+" : ""}#{d.round(2)}" if d.abs > TOLERANCE_PX
        end
      end

      # Operator action: the parked render becomes the baseline. Returns the
      # number of chrome boxes blessed, or nil when nothing is pending.
      def approve(surface_id, root:)
        pending = file(root, surface_id, "pending")
        return nil unless File.file?(pending)

        rects = JSON.parse(File.read(pending))
        write(file(root, surface_id, "baseline"), rects)
        FileUtils.rm_f(pending)
        log("approved #{surface_id}: #{rects.size} chrome box(es) blessed")
        TasteMemory.operator(root:, surface: surface_id, verdict: "approved", note: "chrome baseline blessed")
        rects.size
      end

      def pending(root)
        Dir.glob(File.join(dir(root), "*.pending.json")).map { |p| File.basename(p, ".pending.json") }
      end
    end
  end
end
