# frozen_string_literal: true

require_relative "layout_score_store"

module Master
  module Fix
    # Re-renders surfaces through the same capture API VisualCustody uses and
    # scores them, so a candidate change can be judged on pixels it produced.
    # `measure` is the only method that needs Chrome; callers inject it in tests.
    module LayoutScoreRender
      EPSILON = 0.05

      module_function

      # [[surface, payload], ...] for the given surfaces, in one browser session.
      def measure(surfaces, root:)
        require_relative "../../gates/support/geometry_probe"
        require_relative "../../gates/support/surface_probes"
        return [] unless Deploy::GeometryProbe.available?

        rows = []
        Deploy::GeometryProbe.with_browser(root:, warm: surfaces) do |cdp|
          surfaces.each { |s| rows << [s, Deploy::SurfaceProbes.attach(cdp, s, Deploy::GeometryProbe.walk(cdp, s))] }
        end
        rows
      end

      def scores(measured, root:)
        measured.to_h { |surface, payload| [surface.id, LayoutScoreStore.measure(root, payload).score] }
      end

      # A re-render check for ScaleSnap.apply: true when no surface scores
      # lower than it did when the hook was built.
      def rescore_hook(surfaces, root:, measurer: method(:measure))
        before = scores(measurer.call(surfaces, root:), root:)
        lambda do |_path|
          after = scores(measurer.call(surfaces, root:), root:)
          !before.empty? && before.all? { |id, score| after.fetch(id, 0.0) >= score - EPSILON }
        end
      end
    end
  end
end
