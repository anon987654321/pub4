# frozen_string_literal: true

module Deploy
  module DesignQuality
    BASE_UNIT_PX = 8.0
    SPACE_STEPS_PX = [4.5, 9.0, 13.5, 27.0, 36.0, 54.0, 72.0].freeze
    DENSITY_TARGETS = {
      social: 0.52..0.68,
      luxury: 0.38..0.55,
      face: 0.55..0.75,
      default: 0.45..0.65,
    }.freeze
    MIN_WEIGHT_DELTA = 200

    Element = Struct.new(
      :tag, :role, :text, :x, :y, :w, :h,
      :font_size, :font_weight, :color, :bg_color,
      :is_text, :is_control, :is_image,
      keyword_init: true
    )

    Vector = Struct.new(
      :rhythm, :hierarchy, :density, :alignment, :balance,
      :tap_ok, :contrast_ok,
      keyword_init: true
    ) do
      def soft_axes
        { rhythm:, hierarchy:, density:,
          alignment:, balance: }
      end

      def hard_ok? = tap_ok && contrast_ok

      def regresses?(other, epsilon: 0.03)
        return true unless hard_ok?

        soft_axes.any? { |key, value| value < other.public_send(key) - epsilon }
      end
    end

    module_function

    def calculate(elements:, viewport:, dialect: :default, contrast_ok: true)
      content = content_elements(elements)
      controls = elements.select(&:is_control)

      Vector.new(
        rhythm: rhythm_score(content),
        hierarchy: hierarchy_score(content),
        density: density_score(content, viewport, dialect),
        alignment: alignment_score(content),
        balance: balance_score(content, viewport),
        tap_ok: tap_score(controls),
        contrast_ok:,
      )
    end

    def rhythm_score(elements)
      return 1.0 if elements.size < 2

      gaps = vertical_gaps(elements)
      return 1.0 if gaps.empty?

      (gaps.count { |gap| near_token?(gap) }.to_f / gaps.size).clamp(0.0, 1.0)
    end

    def hierarchy_score(elements)
      texts = elements.select { |element| element.is_text && element.font_size.to_f > 0 }
      return 0.4 if texts.size < 2

      sizes = texts.map { |element| element.font_size.to_f }
      weights = texts.map { |element| element.font_weight.to_i }
      size_ratio = sizes.max / [sizes.min, 1.0].max
      weight_delta = weights.max - weights.min
      size_part = ((size_ratio - 1.0) / 1.5).clamp(0.0, 1.0)
      weight_part = (weight_delta / 400.0).clamp(0.0, 1.0)
      weight_part = 0.0 if weight_delta < MIN_WEIGHT_DELTA

      (0.6 * size_part + 0.4 * weight_part).clamp(0.0, 1.0)
    end

    def density_score(elements, viewport, dialect)
      return 0.5 if elements.empty?

      content_area = elements.sum { |element| element.w.to_f * element.h.to_f }
      viewport_area = viewport[:w].to_f * viewport[:h].to_f
      return 0.5 if viewport_area <= 0

      occupied = (content_area / viewport_area).clamp(0.0, 1.0)
      target = DENSITY_TARGETS.fetch(dialect.to_sym, DENSITY_TARGETS[:default])

      return 1.0 if target.cover?(occupied)
      return (occupied / target.begin).clamp(0.0, 1.0) if occupied < target.begin

      excess = occupied - target.end
      (1.0 - excess / (1.0 - target.end)).clamp(0.0, 1.0)
    end

    def alignment_score(elements)
      return 1.0 if elements.size < 2

      lefts = elements.map { |element| element.x.round }
      rights = elements.map { |element| (element.x + element.w).round }
      centers = elements.map { |element| (element.x + element.w / 2).round }
      unique = (lefts + rights + centers).uniq.size
      (1.0 - unique.to_f / (elements.size * 3)).clamp(0.0, 1.0)
    end

    def balance_score(elements, viewport)
      return 1.0 if elements.empty?

      mid_x = viewport[:w].to_f / 2.0
      left = elements.select { |element| element.x + element.w / 2.0 < mid_x }
        .sum { |element| element.w.to_f * element.h.to_f }
      right = elements.select { |element| element.x + element.w / 2.0 >= mid_x }
        .sum { |element| element.w.to_f * element.h.to_f }
      total = left + right
      return 1.0 if total <= 0

      (1.0 - ((left - right).abs / total)).clamp(0.0, 1.0)
    end

    def tap_score(controls)
      return true if controls.empty?

      controls.all? { |control| control.h.to_f >= 44.0 && control.w.to_f >= 44.0 }
    end

    def content_elements(elements)
      elements.select { |element| element.is_text || element.is_image || element.is_control }
    end

    def vertical_gaps(elements)
      elements.sort_by { |element| [element.y, element.x] }.each_cons(2).filter_map do |a, b|
        gap = b.y.to_f - (a.y.to_f + a.h.to_f)
        gap if gap > 0 && gap < 200
      end
    end

    def near_token?(gap)
      SPACE_STEPS_PX.any? { |step| (gap - step).abs <= 2.0 } ||
        (gap % BASE_UNIT_PX).abs <= 1.5
    end
  end
end
