# frozen_string_literal: true

require "vips"

module Bridges
  module Postpro
    class VipsEffects
      DEFAULT_QUALITY = 85
      DEFAULT_STRIP = true
      DEFAULT_SRGB = true

      DEFAULT_BLUR_SIGMA = 1.2
      DEFAULT_SHARPEN_SIGMA = 1.0
      DEFAULT_SHARPEN_X1 = 2.0
      DEFAULT_SHARPEN_Y2 = 10.0
      DEFAULT_GAMMA = 2.2

      DEFAULT_THUMB_SIZE = 512
      DEFAULT_WATERMARK_OPACITY = 0.35

      ROTATE_90 = 90
      ROTATE_180 = 180
      ROTATE_270 = 270

      class << self
        def load_image(path)
          return nil if path.to_s.strip.empty?

          Vips::Image.new_from_file(path)
        rescue StandardError => e
          Logging.warn("VipsEffects.load_image error=#{e.class} message=#{e.message} path=#{path.inspect}")
          nil
        end

        def apply(image, options = {})
          return nil if image.nil?

          pipeline = normalize_options(options)

          result = image
          result = ensure_srgb(result) if pipeline[:srgb]
          result = strip_metadata(result) if pipeline[:strip]
          result = resize(result, pipeline[:resize]) if pipeline[:resize]
          result = rotate(result, pipeline[:rotate]) if pipeline[:rotate]
          result = blur(result, pipeline[:blur]) if pipeline[:blur]
          result = sharpen(result, pipeline[:sharpen]) if pipeline[:sharpen]
          result = gamma(result, pipeline[:gamma]) if pipeline[:gamma]
          result = watermark(result, pipeline[:watermark]) if pipeline[:watermark]

          result
        end

        def save_jpeg(image, path, options = {})
          return nil if image.nil?
          return nil if path.to_s.strip.empty?

          quality = options.fetch(:quality, DEFAULT_QUALITY)

          image.jpegsave(path, Q: quality)
          path
        rescue StandardError => e
          Logging.warn(
            "VipsEffects.save_jpeg error=#{e.class} message=#{e.message} path=#{path.inspect} quality=#{quality.inspect}"
          )
          nil
        end

        def thumbnail(path, size: DEFAULT_THUMB_SIZE, options: {})
          return nil if path.to_s.strip.empty?

          image = load_image(path)
          return nil if image.nil?

          resized = resize(image, width: size, height: size, fit: :inside)
          apply(resized, options)
        rescue StandardError => e
          Logging.warn("VipsEffects.thumbnail error=#{e.class} message=#{e.message} path=#{path.inspect} size=#{size.inspect}")
          nil
        end
      end

      private

      class << self
        def normalize_options(options)
          opts = options.is_a?(Hash) ? options : {}

          {
            srgb: opts.fetch(:srgb, DEFAULT_SRGB),
            strip: opts.fetch(:strip, DEFAULT_STRIP),
            resize: opts[:resize],
            rotate: opts[:rotate],
            blur: opts[:blur],
            sharpen: opts[:sharpen],
            gamma: opts[:gamma],
            watermark: opts[:watermark]
          }
        end

        def ensure_srgb(image)
          image.colourspace("srgb")
        rescue StandardError => e
          Logging.warn("VipsEffects.ensure_srgb error=#{e.class} message=#{e.message}")
          nil
        end

        def strip_metadata(image)
          image.copy(interpretation: image.interpretation)
        rescue StandardError => e
          Logging.warn("VipsEffects.strip_metadata error=#{e.class} message=#{e.message}")
          nil
        end

        def resize(image, resize_options)
          return image if resize_options.nil?

          resize_hash = resize_options.is_a?(Hash) ? resize_options : {}
          width = resize_hash[:width]
          height = resize_hash[:height]
          fit = resize_hash.fetch(:fit, :inside)

          return image if width.nil? && height.nil?

          if fit == :cover
            cover_resize(image, width, height)
          else
            inside_resize(image, width, height)
          end
        rescue StandardError => e
          Logging.warn("VipsEffects.resize error=#{e.class} message=#{e.message} opts=#{resize_options.inspect}")
          nil
        end

        def inside_resize(image, width, height)
          target_width = width || image.width
          target_height = height || image.height

          scale_x = target_width.to_f / image.width
          scale_y = target_height.to_f / image.height
          scale = [scale_x, scale_y].min

          return image if scale >= 1.0

          image.resize(scale)
        end

        def cover_resize(image, width, height)
          return image if width.nil? || height.nil?

          scale_x = width.to_f / image.width
          scale_y = height.to_f / image.height
          scale = [scale_x, scale_y].max

          resized = image.resize(scale)

          left = [(resized.width - width) / 2, 0].max
          top = [(resized.height - height) / 2, 0].max

          resized.crop(left, top, width, height)
        end

        def rotate(image, rotate_value)
          degrees = Integer(rotate_value) rescue nil
          return image if degrees.nil?

          case degrees
          when ROTATE_90
            image.rot90
          when ROTATE_180
            image.rot180
          when ROTATE_270
            image.rot270
          else
            image
          end
        rescue StandardError => e
          Logging.warn("VipsEffects.rotate error=#{e.class} message=#{e.message} rotate=#{rotate_value.inspect}")
          nil
        end

        def blur(image, blur_options)
          blur_hash = blur_options.is_a?(Hash) ? blur_options : {}
          sigma = blur_hash.fetch(:sigma, DEFAULT_BLUR_SIGMA)
          image.gaussblur(sigma)
        rescue StandardError => e
          Logging.warn("VipsEffects.blur error=#{e.class} message=#{e.message} opts=#{blur_options.inspect}")
          nil
        end

        def sharpen(image, sharpen_options)
          sharpen_hash = sharpen_options.is_a?(Hash) ? sharpen_options : {}
          sigma = sharpen_hash.fetch(:sigma, DEFAULT_SHARPEN_SIGMA)
          x1 = sharpen_hash.fetch(:x1, DEFAULT_SHARPEN_X1)
          y2 = sharpen_hash.fetch(:y2, DEFAULT_SHARPEN_Y2)

          image.sharpen(sigma: sigma, x1: x1, y2: y2)
        rescue StandardError => e
          Logging.warn("VipsEffects.sharpen error=#{e.class} message=#{e.message} opts=#{sharpen_options.inspect}")
          nil
        end

        def gamma(image, gamma_options)
          gamma_hash = gamma_options.is_a?(Hash) ? gamma_options : {}
          value = gamma_hash.fetch(:value, DEFAULT_GAMMA)
          image.gamma(exponent: value)
        rescue StandardError => e
          Logging.warn("VipsEffects.gamma error=#{e.class} message=#{e.message} opts=#{gamma_options.inspect}")
          nil
        end

        def watermark(image, watermark_options)
          watermark_hash = watermark_options.is_a?(Hash) ? watermark_options : {}
          watermark_path = watermark_hash[:path]
          return image if watermark_path.to_s.strip.empty?

          opacity = watermark_hash.fetch(:opacity, DEFAULT_WATERMARK_OPACITY)
          position = watermark_hash.fetch(:position, :bottom_right)
          margin = watermark_hash.fetch(:margin, 12)

          watermark_image = load_image(watermark_path)
          return image if watermark_image.nil?

          composed = composite_watermark(image, watermark_image, opacity, position, margin)
          composed || image
        rescue StandardError => e
          Logging.warn("VipsEffects.watermark error=#{e.class} message=#{e.message} opts=#{watermark_options.inspect}")
          nil
        end

        def composite_watermark(base_image, watermark_image, opacity, position, margin)
          watermark_rgba = watermark_image.hasalpha? ? watermark_image : watermark_image.bandjoin(255)

          alpha_band = watermark_rgba.extract_band(watermark_rgba.bands - 1) * opacity
          watermark_with_alpha = watermark_rgba.extract_band(0, n: watermark_rgba.bands - 1).bandjoin(alpha_band)

          left, top = watermark_position(base_image, watermark_with_alpha, position, margin)
          overlay = base_image.composite2(watermark_with_alpha, :over, x: left, y: top)
          overlay
        rescue StandardError => e
          Logging.warn("VipsEffects.composite_watermark error=#{e.class} message=#{e.message} position=#{position.inspect}")
          nil
        end

        def watermark_position(base_image, watermark_image, position, margin)
          max_left = [base_image.width - watermark_image.width - margin, margin].max
          max_top = [base_image.height - watermark_image.height - margin, margin].max

          case position
          when :top_left
            [margin, margin]
          when :top_right
            [max_left, margin]
          when :bottom_left
            [margin, max_top]
          else
            [max_left, max_top]
          end
        end
      end
    end
  end
end