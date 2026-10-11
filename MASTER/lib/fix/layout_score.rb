# frozen_string_literal: true

require_relative "layout_score_tokens"

module Master
  module Fix
    # An objective 0-100 score for one rendered surface at one viewport, computed
    # from the geometry payload a capture already holds. Each sub-score is 0..1
    # and the weights below sum to 1, so the score is reproducible from its parts:
    #
    #   edges    distinct left edges clustered at 2px; <= 6 is full marks, each edge past 6 costs 1/12
    #   grid     line heights and stacked-block gaps on the rhythm unit (1.0), on its half (0.5), else 0
    #   scale    fraction of spacing values (gaps, and any per-element margin/padding/gap the probe reports) on the spacing scale
    #   measure  paragraph line length in characters; 45-75 is full marks, linear to 0 at 20 characters outside
    #   heading  h1-h3 size against the body size as a power of the modular-scale ratio; off-integer exponents lose marks
    #   density  painted share of the viewport; 0.25-0.60 is full marks, linear to 0 at 0 and 1
    #   balance  evenness of vertical gaps between stacked blocks (1 - coefficient of variation)
    #   centering horizontal centroid of painted content against the viewport centre; 4% of the width is free
    #
    # A sub-score with nothing to measure is nil and its weight is redistributed,
    # so a page without paragraphs is not marked down for having no measure.
    module LayoutScore
      WEIGHTS = { "edges" => 0.15, "grid" => 0.15, "scale" => 0.20, "measure" => 0.15,
                  "heading" => 0.10, "density" => 0.10, "balance" => 0.05, "centering" => 0.10 }.freeze
      EDGE_CLUSTER_PX = 2
      EDGE_FREE = 6
      EDGE_SPAN = 12.0
      MEASURE_MIN = 45
      MEASURE_MAX = 75
      MEASURE_SPAN = 20.0
      CHAR_EM = 0.5
      DENSITY_LO = 0.25
      DENSITY_HI = 0.60
      CENTER_FREE = 0.04
      CENTER_SPAN = 0.16
      ON_PX = 1.0
      BLOCK_MIN_W = 24
      Result = Data.define(:score, :subs, :facts)

      module_function

      def compute(payload, tokens:)
        els = Array(payload["elements"]).select { |e| e["visible"] != false && e["onscreen"] != false && e["rect"] }
        gaps = stack_gaps(els, payload)
        facts = { "edges" => 0, "outliers" => 0 }
        subs = {
          "edges" => edges(els, facts), "grid" => grid(els, gaps, tokens),
          "scale" => on_scale(els, gaps, tokens), "measure" => measure(els, facts),
          "heading" => heading(payload, els, tokens), "density" => density(payload, els),
          "balance" => balance(gaps), "centering" => centering(payload, els)
        }
        Result.new(score: combine(subs), subs:, facts:)
      end

      def combine(subs)
        live = WEIGHTS.select { |k, _| subs[k] }
        return 0.0 if live.empty?

        (100.0 * live.sum { |k, w| w * subs[k] } / live.values.sum).round(1)
      end

      def blocks(els) = els.select { |e| (e["text"].to_s != "" || e["interactive"] || e["tag"] == "img") && !e["inline_in_text"] && e["rect"]["w"] >= BLOCK_MIN_W }

      def edges(els, facts)
        xs = blocks(els).map { |e| (e["frect"] || e["rect"])["x"].to_f }.sort
        clusters = xs.slice_when { |a, b| b - a > EDGE_CLUSTER_PX }.to_a.size
        facts["edges"] = clusters
        return if xs.empty?

        clamp(1.0 - [clusters - EDGE_FREE, 0].max / EDGE_SPAN)
      end

      def near?(value, unit) = unit.positive? && ((value % unit)).then { |r| [r, unit - r].min <= ON_PX }

      def rhythm(value, base)
        return 1.0 if near?(value, base)

        near?(value, base / 2.0) ? 0.5 : 0.0
      end

      def grid(els, gaps, tokens)
        lines = els.select { |e| e["text"].to_s != "" && e["line_height"].to_f.positive? }.map { |e| e["line_height"].to_f }
        values = lines + gaps
        return if values.empty?

        base = tokens.base_unit.to_f
        values.sum { |v| rhythm(v, base) } / values.size
      end

      # Vertical gaps between consecutive stacked blocks: the probe's own gaps
      # when it reported them, else derived from the rects.
      def stack_gaps(els, payload)
        reported = Array(payload["gaps"]).map { |g| g["gap"].to_f }.select(&:positive?)
        return reported unless reported.empty?

        rows = blocks(els).map { |e| (e["frect"] || e["rect"]).values_at("y", "h").map(&:to_f) }.sort
        rows.each_cons(2).filter_map { |(y1, h1), (y2, _)| (y2 - (y1 + h1)).then { |g| g if g >= 4 && g <= 128 } }
      end

      def on_scale(els, gaps, tokens)
        values = gaps + els.flat_map { |e| Array(e["spacing"]).map(&:to_f) }.select(&:positive?)
        return if values.empty?

        scale = tokens.space_px
        return if scale.empty?

        values.count { |v| scale.any? { |s| (s - v).abs <= ON_PX } }.to_f / values.size
      end

      def measure(els, facts)
        rows = els.select { |e| e["text_lines"].to_i >= 2 && e["font_size"].to_f.positive? }
        return if rows.empty?

        scores = rows.map do |e|
          chars = e["rect"]["w"] / (e["font_size"].to_f * CHAR_EM)
          off = [MEASURE_MIN - chars, chars - MEASURE_MAX, 0].max
          facts["outliers"] += 1 if off.positive?
          clamp(1.0 - off / MEASURE_SPAN)
        end
        scores.sum / scores.size
      end

      def heading(payload, els, tokens)
        body = body_size(payload, els)
        heads = els.select { |e| e["tag"].to_s.match?(/\Ah[1-3]\z/) && e["font_size"].to_f.positive? }
        return unless body && !heads.empty?

        step = Math.log(tokens.type_ratio)
        scores = heads.map do |h|
          exponent = Math.log(h["font_size"].to_f / body) / step
          next 1.0 if tokens.declared_size?(h["font_size"].to_f)
          next 0.0 if exponent < 0.5

          clamp(1.0 - 2.0 * (exponent - exponent.round).abs)
        end
        scores.sum / scores.size
      end

      def body_size(payload, els)
        median = payload.dig("visual", "typography", "body_median_px")
        return median.to_f if median

        sizes = els.select { |e| e["text"].to_s != "" && !e["tag"].to_s.match?(/\Ah\d\z/) && e["font_size"].to_f >= 10 }.map { |e| e["font_size"].to_f }.sort
        sizes[sizes.size / 2] unless sizes.empty?
      end

      def density(payload, els)
        area = payload["vw"].to_f * payload["vh"].to_f
        return unless area.positive?

        painted = blocks(els).sum { |e| e["rect"]["w"].to_f * e["rect"]["h"].to_f } / area
        painted = payload.dig("visual", "first_screen", "painted_area_ratio_approx").to_f if painted.zero?
        return clamp(painted / DENSITY_LO) if painted < DENSITY_LO

        painted <= DENSITY_HI ? 1.0 : clamp((1.0 - painted) / (1.0 - DENSITY_HI))
      end

      def balance(gaps)
        return if gaps.size < 3

        mean = gaps.sum / gaps.size
        deviation = Math.sqrt(gaps.sum { |g| (g - mean)**2 } / gaps.size)
        clamp(1.0 - deviation / mean)
      end

      def centering(payload, els)
        vw = payload["vw"].to_f
        rows = blocks(els)
        return unless vw.positive? && !rows.empty?

        weight = rows.sum { |e| e["rect"]["w"] * e["rect"]["h"] }
        return unless weight.positive?

        centroid = rows.sum { |e| (e["rect"]["x"] + e["rect"]["w"] / 2.0) * e["rect"]["w"] * e["rect"]["h"] } / weight
        clamp(1.0 - [(centroid - vw / 2).abs / vw - CENTER_FREE, 0].max / CENTER_SPAN)
      end

      def clamp(value) = value.clamp(0.0, 1.0)
    end
  end
end
