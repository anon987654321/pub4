# frozen_string_literal: true

require "digest"

module Postpro
  # Pixel-statistics diagnostics only. This deliberately does not claim to
  # assess composition, focus, intent, or semantic quality.
  module QualityAnalyzer
    def self.report(luminance:, rgb_samples: nil)
      values = Array(luminance).map { |value| Float(value) }.select(&:finite?).map { |v| v.clamp(0.0, 1.0) }
      raise ArgumentError, "luminance samples must not be empty" if values.empty?

      sorted = values.sort
      mean = values.sum / values.length
      p01, p10, p50, p90, p99 = [1, 10, 50, 90, 99].map { |p| percentile(sorted, p) }
      {
        sample_count: values.length,
        exposure: {
          mean_luminance: mean, p01: p01, p99: p99,
          clipped_highlights_pct: percentage(values.count { |v| v >= 0.99 }, values.length),
          clipped_shadows_pct: percentage(values.count { |v| v <= 0.01 }, values.length),
          exposure_bias_stops: exposure_bias(mean)
        },
        tonal: {
          histogram_spread: p90 - p10, black_point: p01, median: p50, white_point: p99,
          shadow_detail_ratio: variance(values.select { |v| v < 0.25 }),
          highlight_detail_ratio: variance(values.select { |v| v > 0.75 })
        },
        contrast: { rms_contrast: Math.sqrt(variance(values)) },
        colour: colour_report(rgb_samples),
        not_assessed: %i[composition focus_quality subject_expression simplicity]
      }
    end

    # Downsample before extracting pixels so reports have a fixed upper
    # cost independent of source resolution. This reports measurable pixel
    # properties, not photographic intent or semantic quality.
    def self.report_image(image, max_dimension: 128)
      raise ArgumentError, "image must respond to thumbnail_image" unless image.respond_to?(:thumbnail_image)
      size = Integer(max_dimension)
      raise ArgumentError, "max_dimension must be between 8 and 512" unless size.between?(8, 512)

      sample = image.thumbnail_image(size, height: size, size: :down).colourspace("srgb").cast("uchar")
      sample = if sample.bands == 1
                 sample.bandjoin([sample, sample])
               elsif sample.bands == 2
                 first = sample.extract_band(0)
                 second = sample.extract_band(1)
                 first.bandjoin([second, first])
               elsif sample.bands > 3
                 sample.extract_band(0, n: 3)
               else
                 sample
               end
      bytes = sample.write_to_memory.unpack("C*")
      raise ArgumentError, "sample image contained no pixels" if bytes.empty? || (bytes.length % 3) != 0

      rgb = bytes.each_slice(3).map { |r, g, b| [r / 255.0, g / 255.0, b / 255.0] }
      luminance = rgb.map { |r, g, b| 0.2126 * r + 0.7152 * g + 0.0722 * b }
      report(luminance: luminance, rgb_samples: rgb).merge(
        dimensions: [image.width, image.height],
        sample_dimensions: [sample.width, sample.height],
        sampling: "uniform thumbnail; encoded-sRGB luminance approximation"
      )
    end

    def self.percentile(sorted, percent)
      return 0.0 if sorted.empty?
      position = (sorted.length - 1) * percent / 100.0
      low = position.floor
      high = position.ceil
      sorted[low] + (sorted[high] - sorted[low]) * (position - low)
    end
    private_class_method :percentile

    def self.variance(values)
      return 0.0 if values.empty?
      mean = values.sum / values.length
      values.sum { |v| (v - mean)**2 } / values.length
    end
    private_class_method :variance

    def self.percentage(count, total)
      count.to_f * 100.0 / total
    end
    private_class_method :percentage

    def self.exposure_bias(mean)
      return 0.0 if mean <= 0.0 || mean >= 1.0
      (Math.log2(0.5 / mean)).clamp(-2.0, 2.0)
    end
    private_class_method :exposure_bias

    def self.colour_report(samples)
      return { available: false, reason: "RGB samples not supplied" } unless samples
      pixels = Array(samples)
      valid = pixels.select { |pixel| pixel.is_a?(Array) && pixel.length >= 3 && pixel.first(3).all? { |v| v.is_a?(Numeric) && v.finite? } }
      return { available: false, reason: "no valid RGB samples" } if valid.empty?

      chroma = valid.map do |r, g, b, *|
        r, g, b = [r, g, b].map { |v| v.clamp(0.0, 1.0) }
        [r - g, r - b]
      end
      { available: true, sample_count: valid.length,
        mean_rg: chroma.sum { |v| v[0] } / chroma.length,
        mean_rb: chroma.sum { |v| v[1] } / chroma.length }
    end
    private_class_method :colour_report
  end
end
