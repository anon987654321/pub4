# frozen_string_literal: true

module Deploy
  class RenderedGeometryCheck
    # Negative space, grouping and the type details the operator asked the visual lane to hold
    # (2026-11-06), read from the probe's element list on the first screen, mobile first:
    #
    #   heading proximity  a heading nearer the block above than the text it introduces  NEGATIVE_SPACE_GROUPING
    #   heading wrap       a heading on 2+ lines that text-wrap does not balance          HEADING_WRAP_BALANCE
    #   body sizes         more than five distinct sizes outside the headings             TYPE_HIERARCHY
    #   edge crowding      text set closer than 8px to a phone's edge                     WHITESPACE_RHYTHM
    #   void               an empty band past a third of the screen between content       NEGATIVE_SPACE_GROUPING
    #   typeface           more than one text family, or monospace outside chat and code  TYPEFACE_PER_ROLE
    #
    # and one line of counts that may only fall: visible elements, distinct colours, painted
    # shadows, distinct left edges, and the empty share of the first screen.
    module SpaceChecks
      HEADING = /\Ah[1-6]\z/
      BODY_SIZES_MAX = 5
      EDGE_FLOOR = 8
      VOID_SHARE = 1.0 / 3
      BALANCED = /balance|pretty/

      def check_space(surface, elements)
        leaves = first_screen_leaves(surface, elements)
        return if leaves.empty?

        space_findings(surface, leaves).each do |kind, (rows, law)|
          next if rows.empty?

          @result.fail("geometry #{kind}: #{surface.id} #{rows.first(4).join("; ")} law=#{law}", severity: :soft)
        end
        counts = minimalism_counts(surface, leaves)
        @result.warn("geometry minimalism: #{surface.id} #{counts} law=AESTHETIC_MINIMALISM")
      end

      def space_findings(surface, leaves)
        {
          "heading_proximity" => [heading_proximity(leaves), "NEGATIVE_SPACE_GROUPING"],
          "heading_wrap" => [heading_wrap(leaves), "HEADING_WRAP_BALANCE"],
          "body_sizes" => [body_sizes(leaves), "TYPE_HIERARCHY"],
          "edge_crowding" => [edge_crowding(surface, leaves), "WHITESPACE_RHYTHM"],
          "void" => [voids(surface, leaves), "NEGATIVE_SPACE_GROUPING"],
          "typeface" => [RenderedDesign::GeometryLaws.typeface_rows(leaves), "TYPEFACE_PER_ROLE"],
        }
      end

      # Elements that paint text of their own, on the first screen.
      def first_screen_leaves(surface, elements)
        Array(elements).select do |el|
          rect = el["frect"]
          el["visible"] && rect && !el["text"].to_s.strip.empty? && rect["y"].to_f < surface.height.to_f
        end
      end

      def heading_proximity(leaves)
        leaves.select { |el| el["tag"].to_s.match?(HEADING) }.filter_map do |heading|
          above = gap_to(heading, leaves, side: :above)
          below = gap_to(heading, leaves, side: :below)
          next unless above && below && above < below

          "#{heading["key"]} sits #{above.round}px under the block above and #{below.round}px over its text"
        end
      end

      # The vertical gap to the nearest element on the given side that shares horizontal span.
      def gap_to(element, leaves, side:)
        box = element["frect"]
        gaps = leaves.filter_map do |other|
          next if other.equal?(element) || !overlaps_x?(box, other["frect"])

          gap = side == :above ? box["y"] - bottom(other["frect"]) : other["frect"]["y"] - bottom(box)
          gap if gap >= 0
        end
        gaps.min
      end

      def overlaps_x?(one, two) = one["x"] < two["x"] + two["w"] && two["x"] < one["x"] + one["w"]

      def bottom(rect) = rect["y"].to_f + rect["h"].to_f

      def heading_wrap(leaves)
        leaves.filter_map do |el|
          next unless el["tag"].to_s.match?(/\Ah[1-3]\z/) && el["text_lines"].to_i >= 2
          next if el["text_wrap"].to_s.match?(BALANCED)

          "#{el["key"]} breaks onto #{el["text_lines"]} lines with text-wrap #{el["text_wrap"] || "wrap"}"
        end
      end

      def body_sizes(leaves)
        sizes = leaves.reject { |el| el["tag"].to_s.match?(HEADING) }.map { |el| el["font_size"].to_f }.uniq.sort
        return [] if sizes.size <= BODY_SIZES_MAX

        ["#{sizes.size} body-side sizes over #{BODY_SIZES_MAX} (#{sizes.join(", ")}px)"]
      end

      # Phones only, and a full-bleed box is a choice, not a crowded line.
      def edge_crowding(surface, leaves)
        width = surface.width.to_f
        return [] if width > 767

        leaves.filter_map do |el|
          margin = edge_margin(el["frect"], width)
          "#{el["key"]} #{margin.round}px from the edge" if margin && margin < EDGE_FLOOR
        end
      end

      def edge_margin(rect, width)
        return if rect["w"].to_f >= width - 1

        [rect["x"].to_f, width - rect["x"].to_f - rect["w"].to_f].min
      end

      # An empty horizontal band between two pieces of content, taller than a third of the screen.
      def voids(surface, leaves)
        spans = leaves.map { |el| [el["frect"]["y"].to_f, bottom(el["frect"])] }.sort
        reach = spans.first.last
        spans.drop(1).filter_map do |top, low|
          gap = top - reach
          reach = [reach, low].max
          "#{gap.round}px empty band above y=#{top.round}" if gap > surface.height.to_f * VOID_SHARE
        end
      end

      def minimalism_counts(surface, leaves)
        rects = leaves.map { |el| el["frect"] }
        colours = leaves.flat_map { |el| [el["color"], el["bg"]] }.compact.uniq.size
        lefts = rects.map { |rect| rect["x"].to_f.round }.uniq.size
        "elements=#{leaves.size} colours=#{colours} shadows=#{leaves.count { |el| el["box_shadow"] }} " \
          "left_edges=#{lefts} empty=#{empty_share(surface, rects)}%"
      end

      def empty_share(surface, rects)
        painted = rects.sum { |rect| rect["w"].to_f * rect["h"].to_f }
        (100 - [painted / (surface.width.to_f * surface.height.to_f) * 100, 100].min).round
      end
    end
  end
end

require_relative "../rendered_design/geometry_laws"
