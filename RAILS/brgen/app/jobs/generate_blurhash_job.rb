# frozen_string_literal: true

class GenerateBlurhashJob < ApplicationJob
  queue_as :bulk

  BASE83 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~".freeze
  MAX_DIMENSION = 32

  def perform(blob_id)
    blob = ActiveStorage::Blob.find_by(id: blob_id)
    return unless blob&.image?
    return if blob.metadata["blurhash"].present?

    blob.open do |file|
      image = Vips::Image.new_from_file(file.path, access: :sequential)
      image = image.colourspace("srgb")
      image = image.resize(scale_factor(image.width, image.height)) if image.width > MAX_DIMENSION || image.height > MAX_DIMENSION
      hash = BlurhashEncoder.encode(image)
      blob.update!(blurhash: hash, metadata: blob.metadata.merge("blurhash" => hash))
    end
  rescue StandardError => e
    Rails.logger.warn("[blurhash] #{e.class}: #{e.message}")
  end

  def scale_factor(width, height)
    [ MAX_DIMENSION.to_f / width.to_f, MAX_DIMENSION.to_f / height.to_f, 1.0 ].min
  end

  module BlurhashEncoder
    module_function

    def encode(image, component_x = 4, component_y = 3)
      width = image.width
      height = image.height
      pixels = build_pixels(image)
      factors = factors_for(width, height, pixels, component_x, component_y)
      actual_max = factors[1..].map { |rgb| rgb.map(&:abs).max }.max || 0.0
      quant_max = quantize_max_value(actual_max)
      hash = +""
      hash << base83_encode((component_x - 1) + (component_y - 1) * 9, 1)
      hash << base83_encode(quant_max, 1)
      hash << base83_encode(encode_dc(factors.first), 4)
      factors[1..].each do |rgb|
        hash << base83_encode(encode_ac(rgb, quant_max_to_actual(quant_max)), 2)
      end
      hash
    end

    def build_pixels(image)
      pixels = []
      image.height.times do |y|
        image.width.times do |x|
          pixel = image.getpoint(x, y)
          r = pixel[0] || 0.0
          g = pixel[1] || r
          b = pixel[2] || r
          pixels << [ srgb_to_linear(r), srgb_to_linear(g), srgb_to_linear(b) ]
        end
      end
      pixels
    end

    def factors_for(width, height, pixels, component_x, component_y)
      factors = []
      component_y.times do |y|
        component_x.times do |x|
          normalization = (x.zero? && y.zero?) ? 1.0 : 2.0
          r = g = b = 0.0
          height.times do |py|
            width.times do |px|
              basis = Math.cos(Math::PI * x * px / width) * Math.cos(Math::PI * y * py / height)
              p = pixels[(py * width) + px]
              r += basis * p[0]
              g += basis * p[1]
              b += basis * p[2]
            end
          end
          scale = normalization / (width * height)
          factors << [ r * scale, g * scale, b * scale ]
        end
      end
      factors
    end

    def encode_dc(rgb)
      r = linear_to_srgb(rgb[0])
      g = linear_to_srgb(rgb[1])
      b = linear_to_srgb(rgb[2])
      (r << 16) + (g << 8) + b
    end

    def encode_ac(rgb, maximum_value)
      quant_r = quantize_ac(rgb[0], maximum_value)
      quant_g = quantize_ac(rgb[1], maximum_value)
      quant_b = quantize_ac(rgb[2], maximum_value)
      quant_r * 19 * 19 + quant_g * 19 + quant_b
    end

    def quantize_ac(value, maximum_value)
      normalized = maximum_value.zero? ? 0.0 : (value / maximum_value)
      quant = (sign_pow(normalized, 0.5) * 9.0 + 9.5).floor
      quant.clamp(0, 18)
    end

    def quantize_max_value(actual_max)
      return 0 if actual_max <= 0

      ((actual_max * 166.0) - 0.5).floor.clamp(0, 82)
    end

    def quant_max_to_actual(quantized_max)
      (quantized_max + 1) / 166.0
    end

    def base83_encode(value, length)
      output = +""
      length.times do |index|
        divisor = 83**(length - index - 1)
        digit = (value / divisor) % 83
        output << BASE83[digit]
      end
      output
    end

    def srgb_to_linear(value)
      v = value.to_f / 255.0
      if v <= 0.04045
        v / 12.92
      else
        ((v + 0.055) / 1.055) ** 2.4
      end
    end

    def sign_pow(value, exponent)
      value.negative? ? -((-value) ** exponent) : value ** exponent
    end

    def linear_to_srgb(value)
      v = value.clamp(0.0, 1.0)
      s = if v <= 0.0031308
            v * 12.92
      else
            1.055 * (v ** (1 / 2.4)) - 0.055
      end
      (s * 255.0 + 0.5).floor.clamp(0, 255)
    end
  end
end
