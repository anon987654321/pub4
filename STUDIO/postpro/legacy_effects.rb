# frozen_string_literal: true

# Creative effects recovered from anon987654321/pub/postpro.
# These compatibility treatments use the current postpro image/runtime helpers.
module Postpro
  module LegacyEffects
    def double_exposure(image, second_image_path = nil, blend_mode = "over", _mode = "professional")
      second = second_image_path.to_s.empty? ? image : load_image(second_image_path)
      raise ArgumentError, "double_exposure: second image could not be loaded" unless second

      second = fit_legacy_image(second, image)
      alpha = 0.45
      one = image.cast("float")
      two = second.cast("float")
      result = case blend_mode.to_s
               when "add" then one + (two * alpha)
               when "multiply" then (one * two) / 255.0
               else (one * (1.0 - alpha)) + (two * alpha)
               end
      safe_cast(result)
    end

    def polaroid_frame(image, intensity = 0.8, border_style = "classic", _mode = "professional")
      i = intensity.to_f.clamp(0.05, 1.0)
      border = [(image.width * 0.035 * i).round, 8].max
      bottom = (border * 1.5).round
      width = image.width + border * 2
      height = image.height + border * 2 + bottom
      frame = Vips::Image.black(width, height, bands: image.bands)
      frame = frame.draw_rect([245] * image.bands, 0, 0, width, height, fill: true)
      if border_style.to_s == "worn"
        inner = frame.draw_rect([216] * image.bands, border / 2, border / 2,
                                width - border, height - border, fill: true)
      else
        inner = frame
      end
      safe_cast(inner.composite2(image, "over", x: border, y: border))
    end

    def tape_degradation(image, intensity = 0.6, _mode = "professional")
      i = intensity.to_f.clamp(0.0, 1.0)
      blur = image.gaussblur([0.5 + i * 1.7, 0.5].max)
      noise = Vips::Image.gaussnoise(image.width, image.height, sigma: 5.0 + 10.0 * i)
      noise = rgb_bands(noise, image.bands)
      result = blur.cast("float") + noise.cast("float") * 0.18
      safe_cast(result)
    end

    def frame_distortion(image, intensity = 0.5, _mode = "professional")
      i = intensity.to_f.clamp(0.0, 1.0)
      angle = 2.5 * i * (((image.width * 13 + image.height * 7) % 3) - 1)
      rotated = image.rotate(angle)
      return image if rotated.width < image.width || rotated.height < image.height

      x = [(rotated.width - image.width) / 2, 0].max
      y = [(rotated.height - image.height) / 2, 0].max
      safe_cast(rotated.crop(x, y, image.width, image.height))
    end

    def super8_flicker(image, intensity = 0.5, _mode = "professional")
      i = intensity.to_f.clamp(0.0, 1.0)
      flicker = Vips::Image.black(image.width, image.height, bands: image.bands)
      count = 3
      seed = (image.width * 31 + image.height * 17).abs
      count.times do |n|
        x = (seed * (n + 3) * 97) % [image.width, 1].max
        y = (seed * (n + 5) * 53) % [image.height, 1].max
        w = [8, (image.width * 0.08).round].max
        h = [6, (image.height * 0.06).round].max
        w = [w, image.width - x].min
        h = [h, image.height - y].min
        flicker = flicker.draw_rect([10 + (n * 3)] * image.bands, x, y, w, h, fill: true)
      end
      safe_cast(image.cast("float") + flicker.gaussblur([image.width / 160.0, 1.0].max) * i)
    end
  end
end


module Postpro
  module LegacyEffects
    def cinemascope_bars(image, intensity = 1.0, aspect_ratio = "2.35:1", _mode = "professional")
      ratio = aspect_ratio.to_s == "1.85:1" ? 1.85 : 2.35
      target_height = (image.width / ratio).round
      gap = [image.height - target_height, 0].max
      bar = (gap * intensity.to_f.clamp(0.0, 1.0) / 2.0).round
      return image if bar.zero?

      bars = Vips::Image.black(image.width, image.height, bands: image.bands)
      bars = bars.draw_rect([0] * image.bands, 0, 0, image.width, bar, fill: true)
      bars = bars.draw_rect([0] * image.bands, 0, image.height - bar, image.width, bar, fill: true)
      safe_cast(bars.composite2(image, "over"))
    end

    def halftone_print(image, intensity = 0.6, _mode = "professional")
      i = intensity.to_f.clamp(0.0, 1.0)
      grey = image.colourspace("b-w")
      dots = grey.rank(7, 7, 0).gaussblur(2.0)
      dots = rgb_bands(dots, image.bands)
      result = image.cast("float") * (1.0 - 0.18 * i) + dots.cast("float") * (0.18 * i)
      safe_cast(result)
    end

    def film_scratches(image, intensity = 0.45, _mode = "professional")
      i = intensity.to_f.clamp(0.0, 1.0)
      scratches = Vips::Image.black(image.width, image.height, bands: image.bands)
      [1, 3].each_with_index do |gap, n|
        x = ((image.width * (n + 1)) / 3.0).round
        width = [1, (image.width * 0.0015).round].max
        scratches = scratches.draw_rect([8 + n * 4] * image.bands, x, 0, width, image.height, fill: true)
      end
      scratches = scratches.gaussblur([image.width / 1200.0, 0.35].max)
      safe_cast(image.cast("float") + scratches.cast("float") * (0.8 * i))
    end

    # Compatibility name routed through the current measured film model.
    def film_stock_emulation(image, intensity = 0.8, stock_type = "kodak_portra", _mode = "professional")
      stock = stock_type.to_s.to_sym
      stock = :kodak_portra unless STOCKS.key?(stock)
      strength = intensity.to_f.clamp(0.0, 1.0)
      result = film_curve(image, stock, strength)
      result = stock_matrix(result, stock, strength * 0.8) if respond_to?(:stock_matrix, true)
      result
    end

    def sprocket_holes(image, intensity = 0.8, _mode = "professional")
      i = intensity.to_f.clamp(0.0, 1.0)
      border = [8, (image.width * 0.025 * i).round].max
      frame = Vips::Image.black(image.width + border * 2, image.height, bands: image.bands)
      frame = frame.draw_rect([238] * image.bands, 0, 0, frame.width, frame.height, fill: true)
      spacing = [18, (image.height / 18.0).round].max
      (0..(image.height / spacing)).each do |n|
        y = n * spacing
        break if y + border > image.height
        frame = frame.draw_rect([0] * image.bands, 0, y, border, border, fill: true)
        frame = frame.draw_rect([0] * image.bands, frame.width - border, y, border, border, fill: true)
      end
      safe_cast(frame.composite2(image, "over", x: border, y: 0))
    end

    def lens_flare(image, intensity = 0.5, _mode = "professional")
      i = intensity.to_f.clamp(0.0, 1.0)
      flare = Vips::Image.black(image.width, image.height, bands: image.bands)
      y = (image.height * 0.31).round
      x = (image.width * 0.18).round
      length = [40, (image.width * (0.18 + 0.18 * i)).round].max
      x2 = [x + length, image.width - 1].min
      flare = flare.draw_line([255, 188, 132], x, y, x2, y)
      flare = flare.gaussblur([image.width / 240.0, 1.2].max)
      safe_cast(image.cast("float") + flare.cast("float") * (0.20 * i))
    end
  end
end
