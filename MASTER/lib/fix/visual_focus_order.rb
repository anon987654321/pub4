# frozen_string_literal: true

module Master
  module Fix
    # Tab order against reading order. The probe records the stops Chrome's Tab
    # key actually visited, with their boxes; this reads them as the eye does,
    # top to bottom and, within a row, along the language direction, and names
    # each stop that jumps backwards. A payload without a recorded sequence
    # (an old baseline, a probe that could not press Tab) falls back to
    # document order, which is the tab order only when no tabindex or CSS
    # reordering is at work.
    module VisualFocusOrder
      JUMP_PX = 40

      module_function

      # Stops (rows with "key") that sit before their predecessor in reading order.
      def inversions(els, payload)
        stops = recorded(payload) || dom_stops(els)
        rtl = payload["text_dir"] == "rtl"
        stops.each_cons(2).filter_map { |a, b| b if before?(b, a, rtl) }
      end

      def recorded(payload)
        order = payload["tab_order"]
        return unless order.is_a?(Array) && order.any?

        order.reject { |s| s["position"] == "fixed" }
             .map { |s| { "key" => (s["key"] || s["sel"]).to_s, "x" => s["x"].to_f, "y" => s["y"].to_f, "w" => s["w"].to_f, "h" => s["h"].to_f } }
      end

      def dom_stops(els)
        els.select { |e| e["interactive"] && e["onscreen"] != false && e["position"] != "fixed" && e["rect"] }
           .map { |e| { "key" => e["key"].to_s, "x" => e["rect"]["x"].to_f, "y" => e["rect"]["y"].to_f, "w" => e["rect"]["w"].to_f, "h" => e["rect"]["h"].to_f } }
      end

      # b precedes a when it is clearly above, or on the same row and clearly
      # further along the reading direction's start. Between "same row" and a
      # full JUMP_PX the pair is ambiguous and is left alone.
      def before?(b, a, rtl)
        dy = (b["y"] + (b["h"] / 2)) - (a["y"] + (a["h"] / 2))
        same_row = dy.abs <= [[a["h"], b["h"]].min / 2, 4].max.clamp(4, JUMP_PX)
        return dy < -JUMP_PX unless same_row

        rtl ? b["x"] + b["w"] > a["x"] + a["w"] + JUMP_PX : b["x"] + JUMP_PX < a["x"]
      end
    end
  end
end
