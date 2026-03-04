# frozen_string_literal: true

require "vips"

module Bridges
  module Postpro
    class VipsEffects
      DEFAULT_QUALITY = 85
      DEFAULT_BACKGROUND = [255, 255, 255].freeze

      DEFAULT_WATERMARK_OPACITY = 0.35
      DEFAULT_WATERMARK_GRAVITY = :southeast
      WATERMARK_PADDING_PX = 16

      SUPPORTED_OUTPUT_FORMATS = %w[jpg jpeg png webp tiff].freeze

      def initialize(logger: nil)
        @logger = logger
      end

      def render(
        input_path:,
        output_path:,
        resize: nil,
        watermark: nil,
        format: nil,
        quality: DEFAULT_QUALITY,
        flatten: false,
        background: DEFAULT_BACKGROUND
      )
        return false unless path_present?(input_path)
        return false unless path_present?(output_path)

        image = load_image(input_path)
        return false unless image

        image = apply_resize(image, resize) if resize
        image = apply_watermark(image, watermark) if watermark
        image = apply_flatten(image, flatten, background)

        requested_format = format || File.extname(output_path.to_s).delete(".")
        output_format = normalize_format(requested_format)

        return false unless SUPPORTED_OUTPUT_FORMATS.include?(output_format)

        save_image(
          image: image,
          output_path: output_path.to_s,
          format: output_format,
          quality: quality
        )
      end

      private

      def path_present?(path)
        !blank?(path)
      end

      def blank?(value)
        value.to_s.strip.empty?
      end

      def normalize_format(format)
        format.to_s.downcase.strip
      end

      def load_image(input_path)
        Vips::Image.new_from_file(input_path.to_s, access: :sequential)
      rescue Vips::Error => e
        log_error(e)
        nil
      end

      def save_image(image:, output_path:, format:, quality:)
        case format
        when "jpg", "jpeg"
          image.write_to_file(output_path, Q: quality.to_i, strip: true)
        when "png"
          image.write_to_file(output_path, strip: true)
        when "webp"
          image.write_to_file(output_path, Q: quality.to_i, strip: true)
        when "tiff"
          image.write_to_file(output_path, Q: quality.to_i)
        else
          return false
        end

        true
      rescue Vips::Error => e
        log_error(e)
        false
      end

      def apply_resize(image, resize_options)
        target_width = resize_options[:width]
        target_height = resize_options[:height]

        return image unless target_width || target_height

        width = target_width&.to_i
        height = target_height&.to_i

        scale =
          if width && height
            [width.to_f / image.width, height.to_f / image.height].min
          elsif width
            width.to_f / image.width
          elsif height
            height.to_f / image.height
          end

        return image unless scale
        return image unless scale < 1.0

        image.resize(scale)
      end

      def apply_flatten(image, should_flatten, background)
        return image unless should_flatten
        return image unless image.has_alpha?

        r, g, b = background.map(&:to_i)
        image.flatten(background: [r, g, b])
      end

      def apply_watermark(image, watermark_options)
        watermark_path = watermark_options[:path]
        return image unless path_present?(watermark_path)

        watermark_opacity = (watermark_options[:opacity] || DEFAULT_WATERMARK_OPACITY).to_f
        gravity = (watermark_options[:gravity] || DEFAULT_WATERMARK_GRAVITY).to_sym
        scale_factor = watermark_options[:scale]&.to_f

        watermark = load_image(watermark_path)
        return image unless watermark

        watermark = watermark.colourspace("srgb") if watermark.interpretation != :srgb
        watermark = watermark.bandjoin(255) unless watermark.has_alpha?

        watermark =
          if scale_factor && scale_factor.positive?
            watermark.resize(scale_factor)
          else
            watermark
          end

        alpha = watermark.extract_band(watermark.bands - 1) * watermark_opacity
        rgb = watermark.extract_band(0, n: 3)
        watermark_rgba = rgb.bandjoin(alpha)

        left, top = watermark_position_for(
          gravity: gravity,
          base_width: image.width,
          base_height: image.height,
          overlay_width: watermark_rgba.width,
          overlay_height: watermark_rgba.height,
          padding: WATERMARK_PADDING_PX
        )

        image.composite2(watermark_rgba, "over", x: left, y: top)
      end

      def watermark_position_for(gravity:, base_width:, base_height:, overlay_width:, overlay_height:, padding:)
        max_left = [base_width - overlay_width - padding, padding].max
        max_top = [base_height - overlay_height - padding, padding].max
        mid_left = [(base_width - overlay_width) / 2, padding].max
        mid_top = [(base_height - overlay_height) / 2, padding].max

        case gravity
        when :northwest
          [padding, padding]
        when :north
          [mid_left, padding]
        when :northeast
          [max_left, padding]
        when :west
          [padding, mid_top]
        when :center
          [mid_left, mid_top]
        when :east
          [max_left, mid_top]
        when :southwest
          [padding, max_top]
        when :south
          [mid_left, max_top]
        else # :southeast
          [max_left, max_top]
        end
      end

      def log_error(error)
        return unless @logger

        @logger.error(error.message)
      end
    end
  end
end