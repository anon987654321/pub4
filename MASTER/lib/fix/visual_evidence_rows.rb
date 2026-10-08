# frozen_string_literal: true

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

      # One line per surface whose ghost stack measured movement; nil otherwise.
      def drift_row(capture)
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
