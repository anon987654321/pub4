# frozen_string_literal: true

require_relative "../../gates/support/composition_probe"
require_relative "../../gates/support/stress_states"
require_relative "../../gates/support/engine_compare"

module Master
  module Fix
    # The capture side of "does this layout survive real data": for each
    # surface the composition states (clicked controls), then the stress states
    # (long words, zoom, list sizes, rotation, reduced motion, dark), then the
    # same surface in any extra engines. Also the evidence text the council
    # reads about all three, including surfaces too sparse to trust.
    module VisualStress
      SPARSE_MIN = Integer(ENV.fetch("MASTER_VISUAL_SPARSE_MIN", "4"))
      MAX_ROWS = 24

      module_function

      def captures(cdp, surface, dir:, pass:, limit:)
        found = Deploy::CompositionProbe.capture(cdp, surface, dir:, pass:, limit:)
        found + Deploy::StressStates.capture(cdp, surface, dir:, pass:) +
          Deploy::EngineCompare.captures(cdp, surface, dir:)
      end

      def context(captures)
        stress = of_state(captures, "stress")
        engines = of_state(captures, "engine")
        sparse = sparse_rows(captures)
        notes = Deploy::CaptureEngine.unavailable.map { |name, why| "engine #{name}: unavailable (#{why}); not compared" }
        return "STRESS STATES: none captured" if [stress, engines, sparse, notes].all?(&:empty?)

        <<~TEXT
          STRESS STATES
          Figures labelled __stress_<state> re-render a surface under long Norwegian compound words, a 320px screen, 200% zoom, lists of 0, 1 and 200 items, a phone on its side, reduced motion and dark. Findings listed are new relative to the resting render. Fix the layout (wrapping, min-width: 0, overflow, flex-wrap), never the data. A state the stylesheet has no rule for is not captured.
          #{(stress_rows(stress) + engine_rows(engines) + sparse + notes).first(MAX_ROWS).join("\n")}
        TEXT
      end

      def of_state(captures, state)
        Array(captures).select { |c| c.dig(:payload, "composition", "state") == state }
      end

      def stress_rows(captures)
        captures.flat_map do |capture|
          id = capture[:surface].id
          findings = Array(capture.dig(:payload, "stress", "findings"))
          next ["#{id}: no new layout failures"] if findings.empty?

          findings.map do |f|
            more = f["similar"].to_i.positive? ? " (+#{f["similar"]} like it)" : ""
            "#{id}: #{f["kind"]} #{f["selector"]} — #{f["detail"]}#{more}"
          end
        end
      end

      def engine_rows(captures)
        captures.flat_map do |capture|
          result = capture.dig(:payload, "engine") || {}
          id = capture[:surface].id
          head = "#{id}: #{result["diverging"].to_i} of #{result["compared"].to_i} boxes differ from chrome by more than #{result["tolerance"]}px"
          [head, *Array(result["divergences"]).first(5).map { |d| "#{id}: #{d["key"]} moved #{d["delta"].map { |axis, v| "#{axis}#{v >= 0 ? "+" : ""}#{v}" }.join(" ")}" }]
        end
      end

      # A list-like container with fewer items than a real feed would hold.
      def sparse_rows(captures)
        seen = {}
        of_state(captures, "stress").each do |capture|
          list = capture.dig(:payload, "stress", "list")
          base = capture.dig(:payload, "composition", "base_surface")
          seen[base] ||= list
        end
        seen.filter_map do |base, list|
          next unless list && list["count"].to_i < SPARSE_MIN

          "sparse surface #{base}: #{list["selector"]} holds #{list["count"]} items (< #{SPARSE_MIN}); empty data hides layout bugs — run `MASTER/bin/operator visual seed` to load believable local content"
        end
      end
    end
  end
end
