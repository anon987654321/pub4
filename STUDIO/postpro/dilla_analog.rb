# frozen_string_literal: true

# Still-image translations of mechanisms used by STUDIO/dilla's analog chains.
# These are physical analogies, not literal audio filters: temporal processes
# such as wow/flutter become spatial registration, while nonlinear and spectral
# behaviour becomes luminance/texture structure.
module Postpro
  module DillaAnalog
    NASTY_PHASE_OFFSETS = [0, 13, 29, 47].freeze

    DILLA_ANALOG_PRESETS = {
      "vinyl_hot" => %i[dilla_head_bump dilla_vinyl_bandlimit dilla_phasy],
      "summing_phasy" => %i[dilla_head_bump dilla_phasy],
      "acetate" => %i[dilla_head_bump dilla_tape_saturation dilla_vinyl_bandlimit],
      "tape" => %i[dilla_head_bump dilla_tape_saturation dilla_vinyl_bandlimit],
      "night_bus" => %i[dilla_head_bump dilla_tape_saturation dilla_phasy],
    }.freeze

    def dilla_head_bump(image, intensity = 0.5)
      i = intensity.to_f.clamp(0.0, 1.0)
      return image if i.zero?

      luma = image.colourspace("b-w").cast("float")
      broad = luma.gaussblur([image.width / 180.0, 1.5].max)
      band = broad - broad.gaussblur([image.width / 70.0, 3.0].max)
      lift = rgb_bands(band, image.bands)
      safe_cast(image.cast("float") + lift.cast("float") * (2.8 * i))
    end

    def dilla_tape_saturation(image, intensity = 0.5)
      i = intensity.to_f.clamp(0.0, 1.0)
      x = image.cast("float") / 255.0
      drive = 0.35 + 1.15 * i
      curved = (x * (1.0 + drive)) / (1.0 + (x * drive))
      # Dilla's tape chain also rolls the top; keep it gentle enough to preserve
      # the current film curve and let the image's own stock decide colour.
      result = (curved * 255.0).gaussblur([image.width / 2600.0, 0.15].max)
      safe_cast(image.cast("float") * (1.0 - 0.35 * i) + result.cast("float") * (0.35 * i))
    end

    def dilla_vinyl_bandlimit(image, intensity = 0.5)
      i = intensity.to_f.clamp(0.0, 1.0)
      radius = [image.width / 950.0, 0.45].max
      softened = image.gaussblur(radius)
      # A vinyl-like bandwidth loss should be a restrained high-frequency roll,
      # not a blur that erases the photograph.
      safe_cast(image.cast("float") * (1.0 - 0.16 * i) +
                softened.cast("float") * (0.16 * i))
    end

    def dilla_phasy(image, intensity = 0.5)
      i = intensity.to_f.clamp(0.0, 1.0)
      return image if i.zero?

      r, g, b = image.bandsplit
      scale = [image.width / 1800.0, 0.35].max * i
      offsets = NASTY_PHASE_OFFSETS
      red = r.roll((offsets[1] * scale).round, 0)
      green = g
      blue = b.roll(-(offsets[2] * scale).round, 0)
      shifted = Vips::Image.bandjoin([red, green, blue]).cast("float")
      safe_cast(image.cast("float") * (1.0 - 0.20 * i) + shifted * (0.20 * i))
    end

    def dilla_console_sum(image, intensity = 0.5)
      i = intensity.to_f.clamp(0.0, 1.0)
      summed = (0..3).map do |index|
        shifted = if index.zero?
                    image
                  else
                    delta = ((NASTY_PHASE_OFFSETS[index] * [image.width / 1800.0, 0.35].max * i).round)
                    image.roll(delta, index.even? ? delta / 2 : -(delta / 2))
                  end
        d = 0.18 + index * 0.07
        dilla_tape_saturation(shifted, d)
      end
      result = summed.reduce { |a, b| a.cast("float") + b.cast("float") } / summed.length.to_f
      safe_cast(result)
    end

    private

    def dilla_analog_enabled?(name)
      DILLA_ANALOG_PRESETS.key?(name.to_s)
    end
  end
end
