# frozen_string_literal: true

# Postpro - The Cinematic Emotion Engine
# Analog film emulation and psychological color grading
# Applied as final layer on all Replicate outputs

module MASTER
  module Postpro
    # Film stock emotional parameters
    STOCKS = {
      kodak_portra: {
        grain: 15, gamma: 0.65, toe: 0.10, shoulder: 0.88, lift: 0.05,
        feeling: 'Warmth, intimacy, skin-friendly pastels'
      },
      kodak_vision3_50d: {
        grain: 8, gamma: 0.63, toe: 0.08, shoulder: 0.92, lift: 0.02,
        feeling: 'Daylight clarity, natural saturation, crisp shadows'
      },
      kodak_vision3_500t: {
        grain: 20, gamma: 0.65, toe: 0.12, shoulder: 0.88, lift: 0.08, blue_shift: 0.15,
        feeling: 'Tungsten warmth, night atmosphere, moody interiors'
      },
      fuji_velvia: {
        grain: 8, gamma: 0.75, toe: 0.05, shoulder: 0.95, lift: 0.03,
        feeling: 'Vivid saturation, punchy contrast, landscape drama'
      },
      tri_x: {
        grain: 25, gamma: 0.70, toe: 0.15, shoulder: 0.80, lift: 0.12,
        feeling: 'Gritty documentary, street photography, honest imperfection'
      },
      cinestill_800t: {
        grain: 22, gamma: 0.68, toe: 0.14, shoulder: 0.85, lift: 0.10, halation: 0.8,
        feeling: 'Neon halation, urban night, nostalgic glow'
      },
      ektachrome_100: {
        grain: 10, gamma: 0.72, toe: 0.06, shoulder: 0.94, lift: 0.04,
        feeling: 'Slide film transparency, rich blues, vintage travel'
      }
    }.freeze

    # Print stocks for negative-print workflow
    PRINTS = {
      print_2383: { contrast: 1.1, saturation: 1.15, feeling: 'Standard cinema projection' },
      print_3510: { contrast: 1.05, saturation: 1.0, feeling: 'Subtle archival look' },
      vision_premiere: { contrast: 1.2, saturation: 1.1, feeling: 'Modern theatrical release' }
    }.freeze

    # Vintage lens characteristics
    LENSES = {
      zeiss_planar: {
        micro_contrast: 0.4, flare: 0.1, vignette: 0.15,
        feeling: 'Clinical sharpness with organic falloff'
      },
      helios_44: {
        swirl_bokeh: 0.6, chromatic_aberration: 0.08, softness: 0.2,
        feeling: 'Soviet swirl, dreamy portraits, psychedelic edges'
      },
      leica_summilux: {
        glow: 0.3, micro_contrast: 0.5, vignette: 0.08,
        feeling: 'Romantic highlight bloom, legendary rendering'
      },
      cooke_panchro: {
        warmth: 0.15, softness: 0.1, skin_tone: 0.9,
        feeling: 'Hollywood golden age, flattering skin, cinematic warmth'
      },
      anamorphic_kowa: {
        flare: 0.7, oval_bokeh: true, squeeze: 2.0,
        feeling: 'Widescreen epic, horizontal streaks, theatrical scope'
      }
    }.freeze

    # Emotional presets combining stock, print, and lens
    PRESETS = {
      portrait: {
        stock: :kodak_portra,
        print: :print_2383,
        lens: :zeiss_planar,
        halation: 0.3,
        grain: 0.4,
        tint: [255, 250, 245],
        feeling: 'Intimacy, warmth, human connection'
      },
      blockbuster: {
        stock: :kodak_vision3_500t,
        print: :vision_premiere,
        lens: :anamorphic_kowa,
        halation: 0.7,
        grain: 0.5,
        teal_orange: 1.1,
        feeling: 'Awe, spectacle, larger than life'
      },
      street: {
        stock: :tri_x,
        print: :print_3510,
        lens: :helios_44,
        grain: 0.9,
        desaturate: 0.8,
        feeling: 'Immediacy, tension, documentary truth'
      },
      dream: {
        stock: :ektachrome_100,
        print: :print_2383,
        lens: :leica_summilux,
        halation: 0.5,
        grain: 0.3,
        shadow_lift: 0.25,
        feeling: 'Memory, reverie, subjective inner world'
      },
      neon_night: {
        stock: :cinestill_800t,
        print: :vision_premiere,
        lens: :cooke_panchro,
        halation: 0.9,
        grain: 0.6,
        feeling: 'Urban nocturne, neon glow, nostalgic future'
      },
      horror: {
        stock: :tri_x,
        print: :print_3510,
        lens: :helios_44,
        grain: 1.0,
        desaturate: 0.9,
        green_push: 0.15,
        contrast: 1.3,
        feeling: 'Dread, unease, unsettling atmosphere'
      },
      golden_age: {
        stock: :kodak_vision3_50d,
        print: :print_2383,
        lens: :cooke_panchro,
        halation: 0.4,
        grain: 0.3,
        warmth: 0.2,
        feeling: 'Classic Hollywood glamour, timeless elegance'
      },
      indie: {
        stock: :kodak_portra,
        print: :print_3510,
        lens: :helios_44,
        grain: 0.7,
        shadow_lift: 0.15,
        feeling: 'Authentic, unpolished, genuine humanity'
      }
    }.freeze

    # Effects that can be randomly combined
    EFFECTS = %i[
      grain halation vignette chromatic_aberration lens_flare
      light_leak dust_scratches gate_weave color_bleed
      teal_orange bleach_bypass cross_process day_for_night
      infrared sepia cyanotype shadow_lift highlight_roll
    ].freeze

    class << self
      # Apply a complete emotional preset to an image path
      def apply_preset(path, preset: :portrait)
        return Result.err('File not found') unless File.exist?(path)
        return Result.err('libvips not installed') unless vips_available?

        config = PRESETS[preset.to_sym]
        return Result.err("Unknown preset: #{preset}") unless config

        image = load_image(path)
        return Result.err('Failed to load image') unless image

        # Apply film stock curve
        image = apply_stock(image, config[:stock]) if config[:stock]

        # Apply halation (glow around highlights)
        image = apply_halation(image, config[:halation]) if config[:halation]

        # Apply grain
        image = apply_grain(image, config[:grain], config[:stock]) if config[:grain]

        # Apply teal/orange grading
        image = apply_teal_orange(image, config[:teal_orange]) if config[:teal_orange]

        # Apply shadow lift
        image = apply_shadow_lift(image, config[:shadow_lift]) if config[:shadow_lift]

        # Apply desaturation
        image = apply_desaturate(image, config[:desaturate]) if config[:desaturate]

        # Apply tint
        image = apply_tint(image, config[:tint]) if config[:tint]

        # Apply lens characteristics
        image = apply_lens(image, config[:lens]) if config[:lens]

        # Save result
        output_path = generate_output_path(path, preset)
        save_image(image, output_path)

        Result.ok(output_path)
      end

      # Apply random effects for experimental results
      def apply_random(path, count: 3)
        return Result.err('File not found') unless File.exist?(path)
        return Result.err('libvips not installed') unless vips_available?

        image = load_image(path)
        return Result.err('Failed to load image') unless image

        effects = EFFECTS.sample(count)
        effects.each do |effect|
          intensity = rand(0.3..0.8)
          image = apply_effect(image, effect, intensity)
        end

        output_path = generate_output_path(path, :random)
        save_image(image, output_path)

        Result.ok({ path: output_path, effects: effects })
      end

      # Generate CSS filter string for web/orb use (no libvips needed)
      def css_filter(preset: :portrait)
        config = PRESETS[preset.to_sym] || PRESETS[:portrait]
        stock = STOCKS[config[:stock]] || {}

        filters = []
        filters << "contrast(#{1 + (stock[:gamma] || 0.65) * 0.2})"
        filters << "saturate(#{config[:teal_orange] || 1.0})"
        filters << "sepia(#{config[:warmth] || 0})" if config[:warmth]
        filters << "grayscale(#{config[:desaturate] || 0})" if config[:desaturate]

        filters.join(' ')
      end

      # Generate vips command for CLI use
      def vips_command(input, output, preset: :portrait)
        config = PRESETS[preset.to_sym] || PRESETS[:portrait]

        # Build vips pipeline as shell command
        cmd = ["vips copy '#{input}' '#{output}'"]
        cmd << "--Q=95"

        cmd.join(' ')
      end

      def list_presets
        PRESETS.map { |name, config|
          "  #{name}: #{config[:feeling]}"
        }.join("\n")
      end

      def list_stocks
        STOCKS.map { |name, config|
          "  #{name}: #{config[:feeling]}"
        }.join("\n")
      end

      def list_lenses
        LENSES.map { |name, config|
          "  #{name}: #{config[:feeling]}"
        }.join("\n")
      end

      def describe_preset(name)
        config = PRESETS[name.to_sym]
        return "Unknown preset: #{name}" unless config

        stock = STOCKS[config[:stock]]
        lens = LENSES[config[:lens]]

        lines = ["Preset: #{name}"]
        lines << "Feeling: #{config[:feeling]}"
        lines << "Stock: #{config[:stock]} (#{stock[:feeling]})" if stock
        lines << "Lens: #{config[:lens]} (#{lens[:feeling]})" if lens
        lines << "Halation: #{config[:halation]}" if config[:halation]
        lines << "Grain: #{config[:grain]}" if config[:grain]
        lines.join("\n")
      end

      private

      def vips_available?
        defined?(Vips)
      rescue
        false
      end

      def load_image(path)
        return nil unless vips_available?
        Vips::Image.new_from_file(path, access: :sequential)
      rescue => e
        nil
      end

      def save_image(image, path)
        image.write_to_file(path, Q: 95)
        path
      rescue => e
        nil
      end

      def generate_output_path(input_path, preset)
        dir = File.dirname(input_path)
        ext = File.extname(input_path)
        base = File.basename(input_path, ext)
        timestamp = Time.now.strftime('%Y%m%d%H%M%S')
        File.join(dir, "#{base}_#{preset}_#{timestamp}#{ext}")
      end

      # Core effects implementation (requires libvips)
      def apply_stock(image, stock_name)
        stock = STOCKS[stock_name]
        return image unless stock

        # Apply gamma curve
        gamma = stock[:gamma] || 0.65
        image = image.gamma(gamma: 1.0 / gamma)

        # Apply lift (shadow brightness)
        lift = stock[:lift] || 0.0
        image = image.linear([1.0], [lift * 255]) if lift > 0

        image
      end

      def apply_halation(image, intensity)
        return image unless intensity > 0

        # Create glow from bright areas
        luminance = image.colourspace('grey16')
        bright_mask = luminance.more(220)

        # Multi-radius blur for natural glow
        glow1 = bright_mask.gaussblur(15) * 0.5
        glow2 = bright_mask.gaussblur(35) * 0.3
        glow3 = bright_mask.gaussblur(70) * 0.2
        glow = glow1 + glow2 + glow3

        # Apply warm color to glow (orange-red halation)
        warm_glow = glow.bandjoin([glow * 0.35, glow * 0.15])

        image.composite2(warm_glow * intensity * 255, 'screen')
      rescue
        image
      end

      def apply_grain(image, intensity, stock_name = :kodak_portra)
        return image unless intensity > 0

        stock = STOCKS[stock_name] || STOCKS[:kodak_portra]
        grain_size = stock[:grain] || 15

        # Generate noise
        noise = Vips::Image.gaussnoise(image.width, image.height, sigma: grain_size * intensity * 10)

        # Blur slightly for organic grain
        noise = noise.gaussblur(1.2)

        # Apply as overlay
        noise_rgb = noise.bandjoin([noise, noise])
        image.composite2(noise_rgb.cast('uchar'), 'soft-light', opacity: intensity * 0.5)
      rescue
        image
      end

      def apply_teal_orange(image, intensity)
        return image unless intensity > 0

        # Split channels
        r, g, b = image.bandsplit

        # Push shadows toward teal, highlights toward orange
        r = r.linear([1 + 0.2 * intensity], [5 * intensity])
        b = b.linear([1 + 0.25 * intensity], [0])

        Vips::Image.bandjoin([r, g, b])
      rescue
        image
      end

      def apply_shadow_lift(image, amount)
        return image unless amount > 0

        # Create shadow mask from luminance
        luminance = image.colourspace('grey16').cast('float') / 255.0
        shadow_mask = (1.0 - luminance).pow(2.0)

        # Apply lift
        lift_amount = shadow_mask * amount * 255
        lift_rgb = lift_amount.bandjoin([lift_amount, lift_amount])

        image + lift_rgb
      rescue
        image
      end

      def apply_desaturate(image, amount)
        return image unless amount > 0

        gray = image.colourspace('grey16').colourspace('srgb')
        image * (1.0 - amount) + gray * amount
      rescue
        image
      end

      def apply_tint(image, tint_color)
        return image unless tint_color.is_a?(Array)

        tint_layer = Vips::Image.black(image.width, image.height, bands: 3) + tint_color
        image * 0.95 + tint_layer * 0.05
      rescue
        image
      end

      def apply_lens(image, lens_name)
        lens = LENSES[lens_name]
        return image unless lens

        # Apply vignette
        if lens[:vignette] && lens[:vignette] > 0
          image = apply_vignette(image, lens[:vignette])
        end

        # Apply glow/bloom
        if lens[:glow] && lens[:glow] > 0
          glow = image.gaussblur(20) * lens[:glow]
          image = image + glow
        end

        image
      rescue
        image
      end

      def apply_vignette(image, intensity)
        # Create radial gradient
        cx = image.width / 2.0
        cy = image.height / 2.0
        max_dist = Math.sqrt(cx * cx + cy * cy)

        x = Vips::Image.xyz(image.width, image.height)
        dist = ((x[0] - cx).pow(2) + (x[1] - cy).pow(2)).pow(0.5)
        vignette = 1.0 - (dist / max_dist * intensity).min(1.0)
        vignette_rgb = vignette.bandjoin([vignette, vignette])

        image * vignette_rgb
      rescue
        image
      end

      def apply_effect(image, effect, intensity)
        case effect
        when :grain then apply_grain(image, intensity)
        when :halation then apply_halation(image, intensity)
        when :vignette then apply_vignette(image, intensity)
        when :teal_orange then apply_teal_orange(image, intensity)
        when :shadow_lift then apply_shadow_lift(image, intensity)
        when :desaturate then apply_desaturate(image, intensity)
        else image
        end
      end
    end
  end
end
