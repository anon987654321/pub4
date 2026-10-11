# frozen_string_literal: true

require_relative "dead_css_coverage"
require_relative "cross_app_consistency"
require_relative "visual_cross_page_overlay"
require_relative "fix_trace"
require_relative "layout_score_store"

module Master
  module Fix
    # The two evidence rows VisualPass#build_context adds beside the per-capture
    # rows: marketplace composition alternatives compared as one experiment, and
    # the ghost stack's measured drift. Split from VisualPass at its line ceiling.
    module VisualEvidenceRows
      private

      def composition_variant_context(captures)
        variants = Array(captures).filter_map do |capture|
          surface = capture[:surface]
          match = surface.path.to_s.match(/[?&]design_variant=([^&]+)/)
          next unless match

          variant = match[1]
          spec = Master::Design::Composition.variant(name: "marketplace_sale", variant:)
          [variant, spec.fetch("reference"), spec.fetch("structure"), spec.fetch("signature")]
        end.uniq
        return "MARKETPLACE ALTERNATIVES: none captured" if variants.empty?

        rows = variants.map do |variant, reference, structure, signature|
          "#{variant}: reference=#{reference} structure=#{structure} signature=#{signature}"
        end
        "MARKETPLACE ALTERNATIVES\nCompare these renders as one experiment set. Do not assume the current layout is correct merely because it is established. #{rows.join("\n")}"
      end

      # One line per cross-page group: the picture's numbers, stated in pixels.
      def cross_page_rows(captures)
        VisualCrossPageOverlay.collect(captures).filter_map { |overlay| overlay[:text] }
      end

      # Tells the council what the cross-page images are and how to read them.
      def cross_page_context(captures)
        overlays = VisualCrossPageOverlay.collect(captures)
        return "CROSS-PAGE OVERLAY: none (fewer than two comparable pages)" if overlays.empty?

        <<~TEXT
          CROSS-PAGE OVERLAY
          #{overlays.size} images layer DIFFERENT pages of one app on top of each other at low opacity, top-left aligned at 1:1 pixels, with outlines for header, nav, main, footer and primary actions (one colour per page). Edges shared by every page stay sharp. A double edge, smear or outline offset means chrome that should be one layout primitive differs between pages by a few pixels. The mobile-over-desktop images clip the desktop render to the mobile width without scaling.
          Use them to find structural defects and opportunities across pages: shared layout primitives that should be unified, inconsistent chrome, grid breaks. Anchor each one to a source selector or visible text as for any other finding. A smear proves difference, not error: content-driven height differences are expected.
          #{cross_page_rows(captures).join("\n")}
        TEXT
      end

      # Full-resolution images for the council beyond the contact sheet: the
      # cross-page overlays first, then resting renders in surface order.
      # MASTER_VISUAL_FULLRES_IMAGES caps the count; 0 sends none.
      def fullres_images(captures)
        limit = Integer(ENV.fetch("MASTER_VISUAL_FULLRES_IMAGES", "6"))
        paths = VisualCrossPageOverlay.collect(captures).filter_map { |o| o[:screenshot] }
        paths += Array(captures).map { |c| c[:screenshot] }
        paths.select { |p| p && File.file?(p) }.uniq.first([limit, 0].max).map do |path|
          { path:, name: File.basename(path), mime: "image/png" }
        end
      end

      def cross_page_overlay =(@cross_page ||= VisualCrossPageOverlay.new(dir: @dir))

      # One line per surface whose ghost stack measured movement; nil otherwise.
      def drift_row(capture)
        rows = [LayoutScoreStore.row(capture, root: repo_root), measured_drift_row(capture)].compact
        rows.join("\n") unless rows.empty?
      end

      def measured_drift_row(capture)
        drift = Array(capture.dig(:visual_evidence, :drift))
        design = Array(capture.dig(:visual_evidence, :design_drift))
        return if drift.empty? && design.empty?

        details = drift.first(8).map do |row|
          next "#{row["key"]} #{row["delta"]} #{row["type"]}" unless row["structural"]

          "structural added=#{row["structural"]["added"]} missing=#{row["structural"]["missing"]}"
        end
        details << "design #{design.join("; ")}" unless design.empty?
        "#{capture[:surface].id}: #{details.join(" | ")}"
      end
    end
  end
end
