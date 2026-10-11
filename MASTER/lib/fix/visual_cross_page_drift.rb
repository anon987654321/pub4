# frozen_string_literal: true

module Master
  module Fix
    # Numbers for the cross-page overlay: where the chrome that should be the
    # same on every page of a group (header, nav, main, footer) actually sits,
    # read from each page's geometry payload. A spread above the tolerance is
    # the smear a person would see in the overlay, stated in pixels.
    module VisualCrossPageDrift
      TOLERANCE_PX = 0.5
      MAX_NAV_ITEMS = 6
      MAX_ACTIONS = 4
      MAX_DRIFTED_ROWS = 8
      CHROME_TAGS = %w[header nav main footer].freeze

      module_function

      # Boxes drawn as outlines: landmarks first, then the first few buttons.
      # Each is { name:, rect: { "x"=>, "y"=>, "w"=>, "h"=> } }.
      def boxes(payload)
        elements = Array(payload["elements"])
        landmarks = CHROME_TAGS.filter_map do |tag|
          element = elements.find { |e| e["tag"] == tag }
          box(tag, element)
        end
        actions = elements.select { |e| action?(e) }.first(MAX_ACTIONS).each_with_index.filter_map do |e, index|
          box("action#{index + 1}", e)
        end
        landmarks + actions
      end

      # { "header_h" => 64.0, "nav[0].x" => 12.0, ... } for one page.
      def metrics(payload)
        elements = Array(payload["elements"])
        found = {}
        header = rect_of(elements.find { |e| e["tag"] == "header" })
        found["header_h"] = header["h"] if header
        main = rect_of(elements.find { |e| e["tag"] == "main" })
        found["main_left"] = main["x"] if main
        footer = rect_of(elements.find { |e| e["tag"] == "footer" })
        found["footer_top"] = footer["y"] if footer
        nav_items(elements).first(MAX_NAV_ITEMS).each_with_index do |item, index|
          found["nav[#{index}].x"] = item["x"]
          found["nav[#{index}].y"] = item["y"]
        end
        found
      end

      # Per metric present on two or more pages:
      # { metric:, spread:, min:, max:, values: { surface_id => value } }, widest spread first.
      def rows(pages)
        per_page = pages.to_h { |id, payload| [id, metrics(payload)] }
        names = per_page.values.flat_map(&:keys).uniq
        names.filter_map do |name|
          values = per_page.filter_map { |id, found| [id, found[name]] if found.key?(name) }.to_h
          next if values.size < 2

          { metric: name, spread: (values.values.max - values.values.min).round(2),
            min: values.values.min, max: values.values.max, values: }
        end.sort_by { |row| [-row[:spread], row[:metric]] }
      end

      def drifted(rows) = rows.select { |row| row[:spread] > TOLERANCE_PX }

      # One text line for the council.
      def line(label, rows)
        moved = drifted(rows)
        still = rows.size - moved.size
        parts = moved.first(MAX_DRIFTED_ROWS).map do |row|
          who = row[:values].map { |id, value| "#{id.split("/")[1]}=#{value}" }.join(",")
          "#{row[:metric]} spread=#{row[:spread]}px [#{who}]"
        end
        parts << "stable metrics=#{still}"
        "#{label}: #{moved.empty? ? "no chrome drift" : "chrome drift"} | #{parts.join(" | ")}"
      end

      def action?(element)
        element["interactive"] && (element["tag"] == "button" || element["role"] == "button" ||
          (element["tag"] == "input" && element["input_type"] == "submit"))
      end

      def nav_items(elements)
        elements.select do |e|
          %w[a button].include?(e["tag"]) && e["key"].to_s.split(">").any? { |seg| seg.start_with?("nav") }
        end.filter_map { |e| rect_of(e) }
      end

      def box(name, element)
        rect = rect_of(element)
        rect && rect["w"].to_f.positive? ? { name:, rect: } : nil
      end

      def rect_of(element)
        return unless element

        rect = element["frect"] || element["rect"]
        rect.is_a?(Hash) ? rect.transform_values(&:to_f) : nil
      end
    end
  end
end
