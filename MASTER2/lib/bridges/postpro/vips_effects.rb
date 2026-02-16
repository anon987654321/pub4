# frozen_string_literal: true

module MASTER
  module Bridges
    module PostproBridge
      private

      def load_image(path)
        require "vips"
        Vips::Image.new_from_file(path, access: :sequential)
      rescue StandardError
        nil
      end

      def save_image(image, path)
        image.write_to_file(path, Q: 95)
        path
      rescue StandardError
        nil
      end

      def generate_output_path(input_path, preset)
        dir = File.dirname(input_path)
        ext = File.extname(input_path)
        base = File.basename(input_path, ext)
        timestamp = Time.now.strftime("%Y%m%d%H%M%S")
        File.join(dir, "#{base}_#{preset}_#{timestamp}#{ext}")
      end

      def apply_stock(image, stock_name)
        stock = STOCKS[stock_name]
        return image unless stock

        gamma = stock[:gamma] || 0.65
        image = image.gamma(gamma: 1.0 / gamma)

        lift = stock[:lift] || 0.0
        image = image.linear([1.0], [lift * 255]) if lift > 0

        image
      rescue StandardError
        image
      end

      def apply_halation(image, intensity)
        return image unless intensity > 0

        luminance = image.colourspace("grey16")
        bright_mask = luminance.more(220)

        glow1 = bright_mask.gaussblur(15) * 0.5
        glow2 = bright_mask.gaussblur(35) * 0.3
        glow3 = bright_mask.gaussblur(70) * 0.2
        glow = glow1 + glow2 + glow3

        warm_glow = glow.bandjoin([glow * 0.35, glow * 0.15])
        image.composite2(warm_glow * intensity * 255, "screen")
      rescue StandardError
        image
      end

      def apply_grain(image, intensity, stock_name = :kodak_portra)
        return image unless intensity > 0

        stock = STOCKS[stock_name] || STOCKS[:kodak_portra]
        grain_size = stock[:grain] || 15

        noise = Vips::Image.gaussnoise(image.width, image.height, sigma: grain_size * intensity * 10)
        noise = noise.gaussblur(1.2)
        noise_rgb = noise.bandjoin([noise, noise])
        image.composite2(noise_rgb.cast("uchar"), "soft-light", opacity: intensity * 0.5)
      rescue StandardError
        image
      end

      def apply_teal_orange(image, intensity)
        return image unless intensity > 0

        r, g, b = image.bandsplit
        r = r.linear([1 + 0.2 * intensity], [5 * intensity])
        b = b.linear([1 + 0.25 * intensity], [0])
        Vips::Image.bandjoin([r, g, b])
      rescue StandardError
        image
      end

      def apply_shadow_lift(image, amount)
        return image unless amount > 0

        luminance = image.colourspace("grey16").cast("float") / 255.0
        shadow_mask = (1.0 - luminance).pow(2.0)
        lift_amount = shadow_mask * amount * 255
        lift_rgb = lift_amount.bandjoin([lift_amount, lift_amount])
        image + lift_rgb
      rescue StandardError
        image
      end

      def apply_desaturate(image, amount)
        return image unless amount > 0

        gray = image.colourspace("grey16").colourspace("srgb")
        image * (1.0 - amount) + gray * amount
      rescue StandardError
        image
      end

      def apply_tint(image, tint_color)
        return image unless tint_color.is_a?(Array)

        tint_layer = Vips::Image.black(image.width, image.height, bands: 3) + tint_color
        image * 0.95 + tint_layer * 0.05
      rescue StandardError
        image
      end

      def apply_lens(image, lens_name)
        lens = LENSES[lens_name]
        return image unless lens

        image = apply_vignette_effect(image, lens[:vignette]) if lens[:vignette]&.positive?

        if lens[:glow]&.positive?
          glow = image.gaussblur(20) * lens[:glow]
          image = image + glow
        end

        image
      rescue StandardError
        image
      end

      def apply_vignette_effect(image, intensity)
        cx = image.width / 2.0
        cy = image.height / 2.0
        max_dist = Math.sqrt(cx * cx + cy * cy)

        x = Vips::Image.xyz(image.width, image.height)
        dist = ((x[0] - cx).pow(2) + (x[1] - cy).pow(2)).pow(0.5)
        vignette = 1.0 - (dist / max_dist * intensity).min(1.0)
        vignette_rgb = vignette.bandjoin([vignette, vignette])
        image * vignette_rgb
      rescue StandardError
        image
      end

      def apply_effect(image, effect, intensity)
        case effect
        when :grain then apply_grain(image, intensity)
        when :halation then apply_halation(image, intensity)
        when :vignette then apply_vignette_effect(image, intensity)
        when :teal_orange then apply_teal_orange(image, intensity)
        when :shadow_lift then apply_shadow_lift(image, intensity)
        when :desaturate then apply_desaturate(image, intensity)
        else image
        end
      end
    end
  end
end
