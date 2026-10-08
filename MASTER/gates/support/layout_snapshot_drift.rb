# frozen_string_literal: true

require_relative "design_metrics"

module Deploy
  class LayoutSnapshotGate
    # What a snapshot difference breaks, not only where it is.
    #
    # A flat list in key order put "h1_count: 1 → 2" among fourteen 3px nudges,
    # and the failure line shows eight entries, so a collapsed hierarchy could
    # sit past the end of its own report. Every difference is filed under the
    # damage it does, the classes run most severe first, and emphasis is stated
    # as the ratio a reader perceives rather than the pixel values behind it.
    #
    # The comparison is the gate's, unchanged: the same fields, the same 2px
    # tolerance, the same added and removed keys. Classification sorts and
    # derives; it never drops a difference the flat list reported.
    class Drift
      # Most severe first, and the report keeps this order.
      #
      #   hierarchy  the outline or its emphasis: title, h1 count, landmarks and
      #              their order, h1 against body size, the primary action's
      #              size and contrast against the other actions
      #   wrap       text set on more or fewer lines
      #   density    elements came or went, or the count or content area shifted
      #   reflow     an element crossed a landmark or moved further than a nudge,
      #              or display, position or page width changed
      #   style      colour, background, font size or line height
      #   nudge      moved past rounding but within NUDGE_FACTOR tolerances,
      #              inside the same landmark
      #
      # style is a sixth class because a colour change is none of the other
      # five, and filing it as a nudge would understate it.
      CLASSES = %w[hierarchy wrap density reflow style nudge].freeze

      NUDGE_FACTOR = 4
      # A derived ratio has to move by a tenth of itself to be reported, so a
      # half-pixel font rounding never reads as a hierarchy change.
      RATIO_SHIFT = 0.1
      DENSITY_SHIFT = 0.15
      # A height change counts as a wrap when it lands within a quarter line of
      # a whole number of lines, which padding or a border change does not.
      WRAP_SLACK = 0.25

      LANDMARK_TAGS = %w[header nav main footer aside].freeze
      TEXT_TAGS = %w[h1 h2 a button p label].freeze
      STYLE_FIELDS = %w[color bg font_size line_height].freeze
      FLOW_FIELDS = %w[display position].freeze

      def initialize(baseline, current)
        @was = baseline
        @now = current
        @old = Array(baseline["elements"])
        @new = Array(current["elements"])
        @old_by_key = @old.to_h { |el| [el["key"], el] }
        @new_by_key = @new.to_h { |el| [el["key"], el] }
      end

      def differences
        found = CLASSES.to_h { |name| [name, []] }
        rows = ratios + outline + membership + geometry + styling
        rows.each { |name, text| found.fetch(name) << "#{name}: #{text}" }
        found.values.flatten
      end

      private

      def shared_keys = @old_by_key.keys & @new_by_key.keys

      def ratios
        sizes = [action_ratio(@old) { |el| area(el) }, action_ratio(@new) { |el| area(el) }]
        contrasts = [action_ratio(@old) { |el| contrast(el) }, action_ratio(@new) { |el| contrast(el) }]
        [
          ratio_row("h1/body ratio", heading_ratio(@old), heading_ratio(@new)),
          primary_row,
          ratio_row("primary action size ratio", *sizes),
          ratio_row("primary action contrast ratio", *contrasts),
        ].compact
      end

      def ratio_row(label, was, now)
        return unless was && now && (now - was).abs > was * RATIO_SHIFT

        ["hierarchy", "#{label} #{format('%.2f', was)} → #{format('%.2f', now)}"]
      end

      def heading_ratio(elements)
        heading = elements.select { |el| el["tag"] == "h1" }.filter_map { |el| number(el["font_size"]) }.max
        body = median(elements.reject { |el| %w[h1 h2].include?(el["tag"]) }.filter_map { |el| number(el["font_size"]) })
        heading / body if heading && body&.positive?
      end

      # The largest button, or link styled as one, is the action the page asks
      # for; its siblings are every other action on the surface.
      def actions(elements) = elements.select { |el| el["tag"] == "button" || el["key"].to_s.match?(/\.btn\b/) }

      def primary(elements) = actions(elements).max_by { |el| [area(el), el["key"].to_s] }

      def primary_row
        was = primary(@old)&.fetch("key", nil)
        now = primary(@new)&.fetch("key", nil)
        ["hierarchy", "primary action #{was} → #{now}"] if was && now && was != now
      end

      def action_ratio(elements)
        group = actions(elements)
        return if group.size < 2

        lead = primary(elements)
        mine = yield(lead)
        siblings = median((group - [lead]).filter_map { |el| yield(el) })
        mine.to_f / siblings if mine && siblings&.positive?
      end

      def outline
        rows = %w[title h1_count].map { |field| field_row("hierarchy", field) }
        rows << field_row("reflow", "scroll_width")
        (@was["landmarks"] || {}).each do |mark, was|
          now = @now.dig("landmarks", mark)
          rows << ["hierarchy", "landmark #{mark}: #{was} → #{now}"] if was != now
        end
        rows << landmark_order_row
        rows.compact
      end

      def field_row(name, field)
        return if @was[field] == @now[field]

        [name, "#{field}: #{@was[field].inspect} → #{@now[field].inspect}"]
      end

      # Reading order is top to bottom, then left to right, which is the order a
      # sighted reader meets the landmarks whatever the DOM says.
      def landmark_order_row
        was = landmark_keys(@old)
        now = landmark_keys(@new)
        common = was & now
        return if (was & common) == (now & common)

        ["hierarchy", "landmark order #{(was & common).join(', ')} → #{(now & common).join(', ')}"]
      end

      def landmark_keys(elements)
        elements.select { |el| LANDMARK_TAGS.include?(el["tag"]) }
                .sort_by { |el| [el.dig("rect", "y").to_i, el.dig("rect", "x").to_i, el["key"].to_s] }
                .map { |el| el["key"] }
      end

      def membership
        removed = (@old_by_key.keys - @new_by_key.keys).first(6).map { |key| ["density", "removed: #{key}"] }
        added = (@new_by_key.keys - @old_by_key.keys).first(6).map { |key| ["density", "added: #{key}"] }
        shares = [
          share_row("elements", @old.size, @new.size),
          share_row("content area px²", content_area(@old), content_area(@new)),
        ]
        shares.compact + removed + added
      end

      def share_row(label, was, now)
        return if was == now
        return unless was.zero? || (now - was).abs > was * DENSITY_SHIFT

        ["density", "#{label} #{was} → #{now}"]
      end

      # Landmarks are containers, and a container's box is the sum of what it
      # holds; counting both would charge every change twice.
      def content_area(elements) = elements.reject { |el| LANDMARK_TAGS.include?(el["tag"]) }.sum { |el| area(el) }

      def geometry
        shared_keys.filter_map do |key|
          axes = %w[x y w h].select { |axis| shift(key, axis) > TOLERANCE_PX }
          geometry_row(key, axes) unless axes.empty?
        end
      end

      def geometry_row(key, axes)
        was = @old_by_key[key]
        now = @new_by_key[key]
        detail = axes.map { |axis| "#{axis} #{was.dig('rect', axis)}→#{now.dig('rect', axis)}" }.join(", ")
        lines = wrapped_lines(was, now)
        return ["wrap", "#{key}: #{format('%+d', lines)} line(s) (#{detail})"] if lines

        from = region(@old, was)
        to = region(@new, now)
        return ["reflow", "#{key}: #{from} → #{to} (#{detail})"] if from != to

        near = axes.all? { |axis| shift(key, axis) <= TOLERANCE_PX * NUDGE_FACTOR }
        [near ? "nudge" : "reflow", "#{key}: #{detail}"]
      end

      def shift(key, axis) = (@old_by_key[key].dig("rect", axis).to_i - @new_by_key[key].dig("rect", axis).to_i).abs

      def wrapped_lines(was, now)
        step = number(now["line_height"])
        return unless TEXT_TAGS.include?(now["tag"]) && step&.positive? && was["line_height"] == now["line_height"]

        grown = now.dig("rect", "h").to_f - was.dig("rect", "h").to_f
        lines = (grown / step).round
        lines if lines.nonzero? && (grown - lines * step).abs <= step * WRAP_SLACK
      end

      # The smallest landmark holding the element's centre, other than itself.
      def region(elements, el)
        x = el.dig("rect", "x").to_i + el.dig("rect", "w").to_i / 2
        y = el.dig("rect", "y").to_i + el.dig("rect", "h").to_i / 2
        holders = elements.select do |mark|
          LANDMARK_TAGS.include?(mark["tag"]) && mark["key"] != el["key"] && inside?(mark["rect"] || {}, x, y)
        end
        holders.min_by { |mark| area(mark) }&.fetch("key", nil) || "page"
      end

      def inside?(rect, x, y)
        left = rect["x"].to_i
        top = rect["y"].to_i
        x.between?(left, left + rect["w"].to_i) && y.between?(top, top + rect["h"].to_i)
      end

      def styling
        shared_keys.flat_map { |key| field_rows(key, STYLE_FIELDS, "style") + field_rows(key, FLOW_FIELDS, "reflow") }
      end

      def field_rows(key, fields, name)
        was = @old_by_key[key]
        now = @new_by_key[key]
        fields.reject { |field| was[field] == now[field] }
              .map { |field| [name, "#{key}: #{field} #{was[field].inspect} → #{now[field].inspect}"] }
      end

      def area(el) = el.dig("rect", "w").to_i * el.dig("rect", "h").to_i

      def contrast(el) = DesignMetrics.contrast_ratio(el["color"], el["bg"])

      def number(value) = Float(value, exception: false)

      def median(values)
        return if values.empty?

        sorted = values.sort
        mid = sorted.size / 2
        sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
      end
    end
  end
end
