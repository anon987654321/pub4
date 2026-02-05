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
        when :chromatic_aberration then apply_chromatic_aberration(image, intensity)
        when :lens_flare then apply_lens_flare(image, intensity)
        when :light_leak then apply_light_leak(image, intensity)
        when :dust_scratches then apply_dust_scratches(image, intensity)
        when :gate_weave then apply_gate_weave(image, intensity)
        when :color_bleed then apply_color_bleed(image, intensity)
        when :bleach_bypass then apply_bleach_bypass(image, intensity)
        when :cross_process then apply_cross_process(image, intensity)
        when :day_for_night then apply_day_for_night(image, intensity)
        when :infrared then apply_infrared(image, intensity)
        when :sepia then apply_sepia(image, intensity)
        when :cyanotype then apply_cyanotype(image, intensity)
        when :highlight_roll then apply_highlight_roll(image, intensity)
        when :vhs then apply_vhs(image, intensity)
        when :glitch then apply_glitch(image, intensity)
        when :bloom then apply_bloom(image, intensity)
        else image
        end
      end

      # ─────────────────────────────────────────────────────────────────────
      # Physics-based core transforms
      # ─────────────────────────────────────────────────────────────────────

      def to_linear(image)
        image.gamma(gamma: 2.2)
      end

      def to_gamma(image)
        image.gamma(gamma: 1.0 / 2.2)
      end

      def luminance(image)
        image.colourspace('grey16').cast('float') / 65535.0
      end

      # Attempt noise function (simplified Simplex)
      def simplex2d(x, y)
        n = Math.sin(x * 12.9898 + y * 78.233) * 43758.5453
        n - n.floor
      end

      # ─────────────────────────────────────────────────────────────────────
      # Film stock sensitometric curve
      # ─────────────────────────────────────────────────────────────────────

      def apply_curve(image, stock_name, intensity = 1.0)
        stock = STOCKS[stock_name] || STOCKS[:kodak_portra]

        linear = to_linear(image)
        toe = stock[:toe] || 0.10
        shoulder = stock[:shoulder] || 0.88
        gamma = stock[:gamma] || 0.65
        lift = stock[:lift] || 0.05

        # S-curve approximation
        x = ((linear.log + 3 - toe) / (shoulder - toe)).max(0).min(1)
        curved = (x * x * (3 - 2 * x)) ** (1.0 / gamma)

        result = to_gamma(image * (1 - intensity) + curved.linear(1, lift * 255 * intensity))
        result
      rescue
        image
      end

      # Negative to print workflow (proper film emulation)
      def apply_neg_print(image, negative: :kodak_vision3_500t, print: :print_2383, intensity: 1.0)
        linear = to_linear(image)
        neg = apply_curve(linear, negative, intensity)
        print_stock = PRINTS[print] || PRINTS[:print_2383]
        contrast = print_stock[:contrast] || 1.1
        neg = neg.linear([contrast], [0])
        to_gamma(neg)
      rescue
        image
      end

      # ─────────────────────────────────────────────────────────────────────
      # Luminance-adaptive grain (darker areas get more grain)
      # ─────────────────────────────────────────────────────────────────────

      def apply_adaptive_grain(image, intensity, stock_name = :kodak_portra)
        stock = STOCKS[stock_name] || STOCKS[:kodak_portra]
        grain_size = stock[:grain] || 15

        # Generate noise
        noise = Vips::Image.gaussnoise(image.width, image.height, sigma: grain_size * intensity * 15)

        # Blur for organic look
        coarse = noise.gaussblur(1.5).linear(0.6, 0) + noise.linear(0.4, 0)

        # Luminance-based strength (more grain in shadows)
        lum = luminance(image)
        strength = (2.0 - lum).max(0.8).min(2.0)

        grain_rgb = coarse * strength.bandjoin([strength, strength])
        to_gamma(image.composite2(grain_rgb.cast('uchar') * 0.3, 'soft-light'))
      rescue
        apply_grain(image, intensity, stock_name)
      end

      # ─────────────────────────────────────────────────────────────────────
      # Super8 gate weave (projector instability)
      # ─────────────────────────────────────────────────────────────────────

      def apply_gate_weave(image, intensity)
        t = Time.now.to_f * 10
        ox = simplex2d(t * 0.8, 0) * 18 * intensity
        oy = simplex2d(0, t * 0.8) * 14 * intensity
        rot = simplex2d(t * 0.3, t * 0.4) * 0.8 * intensity

        c = Math.cos(rot * Math::PI / 180)
        s = Math.sin(rot * Math::PI / 180)
        matrix = [c, s, -s, c]

        image.affine(matrix, odx: ox, ody: oy, interpolate: Vips::Interpolate.new('bicubic'))
      rescue
        image
      end

      # ─────────────────────────────────────────────────────────────────────
      # Color effects
      # ─────────────────────────────────────────────────────────────────────

      def apply_color_bleed(image, intensity)
        r, g, b = image.bandsplit
        r_bleed = r.gaussblur(0.8 * intensity * 10)
        g_bleed = g.gaussblur(0.6 * intensity * 10)
        b_bleed = b.gaussblur(1.0 * intensity * 10)
        result = Vips::Image.bandjoin([r_bleed, g_bleed, b_bleed])
        image * (1 - intensity) + result * intensity
      rescue
        image
      end

      def apply_chromatic_aberration(image, intensity)
        r, g, b = image.bandsplit
        shift = (intensity * 5).to_i.clamp(1, 10)

        # Shift red and blue channels in opposite directions
        r_shifted = r.embed(shift, 0, image.width + shift, image.height)
        b_shifted = b.embed(-shift, 0, image.width + shift, image.height)

        Vips::Image.bandjoin([
          r_shifted.crop(0, 0, image.width, image.height),
          g,
          b_shifted.crop(shift * 2, 0, image.width, image.height)
        ])
      rescue
        image
      end

      def apply_bleach_bypass(image, intensity)
        # Desaturate and increase contrast
        gray = image.colourspace('grey16').colourspace('srgb')
        desaturated = image * (1 - intensity * 0.5) + gray * (intensity * 0.5)

        # Boost contrast
        desaturated.linear([1 + intensity * 0.3], [-(intensity * 20)])
      rescue
        image
      end

      def apply_cross_process(image, intensity)
        r, g, b = image.bandsplit

        # Cross process: boost shadows in one channel, highlights in another
        r_cross = r.linear([1 + intensity * 0.2], [intensity * 15])
        g_cross = g.linear([1 - intensity * 0.1], [0])
        b_cross = b.linear([1 + intensity * 0.15], [-(intensity * 10)])

        Vips::Image.bandjoin([r_cross, g_cross, b_cross])
      rescue
        image
      end

      def apply_day_for_night(image, intensity)
        # Heavy blue push, crush blacks
        r, g, b = image.bandsplit

        r_night = r.linear([1 - intensity * 0.5], [-(intensity * 30)])
        g_night = g.linear([1 - intensity * 0.3], [-(intensity * 20)])
        b_night = b.linear([1 + intensity * 0.2], [intensity * 10])

        result = Vips::Image.bandjoin([r_night, g_night, b_night])

        # Darken overall
        result.linear([1 - intensity * 0.4], [0])
      rescue
        image
      end

      def apply_infrared(image, intensity)
        r, g, b = image.bandsplit

        # Swap channels for false color
        # Vegetation (green) becomes white/pink in infrared
        r_ir = g.linear([1 + intensity * 0.5], [intensity * 50])
        g_ir = r.linear([1 - intensity * 0.2], [0])
        b_ir = b.linear([1 - intensity * 0.4], [-(intensity * 20)])

        Vips::Image.bandjoin([r_ir, g_ir, b_ir])
      rescue
        image
      end

      def apply_sepia(image, intensity)
        gray = image.colourspace('grey16').colourspace('srgb')

        # Sepia tint
        r, g, b = gray.bandsplit
        r_sepia = r.linear([1], [intensity * 40])
        g_sepia = g.linear([1], [intensity * 20])
        b_sepia = b.linear([1], [-(intensity * 20)])

        sepia = Vips::Image.bandjoin([r_sepia, g_sepia, b_sepia])
        image * (1 - intensity) + sepia * intensity
      rescue
        image
      end

      def apply_cyanotype(image, intensity)
        gray = image.colourspace('grey16').colourspace('srgb')

        r, g, b = gray.bandsplit
        r_cyan = r.linear([1], [-(intensity * 30)])
        g_cyan = g.linear([1], [intensity * 10])
        b_cyan = b.linear([1], [intensity * 50])

        cyan = Vips::Image.bandjoin([r_cyan, g_cyan, b_cyan])
        image * (1 - intensity) + cyan * intensity
      rescue
        image
      end

      # ─────────────────────────────────────────────────────────────────────
      # Light effects
      # ─────────────────────────────────────────────────────────────────────

      def apply_lens_flare(image, intensity)
        # Create circular gradient for flare
        cx = image.width * (0.3 + rand * 0.4)
        cy = image.height * (0.2 + rand * 0.3)

        x = Vips::Image.xyz(image.width, image.height)
        dist = ((x[0] - cx).pow(2) + (x[1] - cy).pow(2)).pow(0.5)

        flare_radius = [image.width, image.height].min * 0.15
        flare = (1.0 - (dist / flare_radius).min(1.0)).pow(2)

        # Warm flare color
        flare_color = flare.bandjoin([flare * 0.8, flare * 0.4])
        image + flare_color * intensity * 100
      rescue
        image
      end

      def apply_light_leak(image, intensity)
        # Create gradient from corner
        corner = rand(4)
        x = Vips::Image.xyz(image.width, image.height)

        case corner
        when 0 then dist = x[0] + x[1]
        when 1 then dist = (image.width - x[0]) + x[1]
        when 2 then dist = x[0] + (image.height - x[1])
        else dist = (image.width - x[0]) + (image.height - x[1])
        end

        max_dist = image.width + image.height
        leak = (1.0 - dist / max_dist).pow(3)

        # Random warm/cool leak
        if rand < 0.5
          leak_color = leak.bandjoin([leak * 0.6, leak * 0.2]) # Orange
        else
          leak_color = (leak * 0.3).bandjoin([leak * 0.5, leak]) # Cyan
        end

        image.composite2(leak_color * intensity * 150, 'screen')
      rescue
        image
      end

      def apply_bloom(image, intensity)
        # Soft glow from highlights
        bright = image.more(200)
        glow = bright.gaussblur(30) * 0.5 + bright.gaussblur(60) * 0.3 + bright.gaussblur(100) * 0.2

        image + glow * intensity * 0.5
      rescue
        image
      end

      def apply_highlight_roll(image, intensity)
        # Smooth highlight rolloff (like film)
        linear = to_linear(image)
        compressed = linear.pow(1.0 + intensity * 0.3)
        to_gamma(compressed)
      rescue
        image
      end

      # ─────────────────────────────────────────────────────────────────────
      # Texture and damage effects
      # ─────────────────────────────────────────────────────────────────────

      def apply_dust_scratches(image, intensity)
        # Create noise for dust
        dust = Vips::Image.gaussnoise(image.width, image.height, sigma: 1)
        dust_mask = dust.more(250 - intensity * 20)

        # Vertical lines for scratches
        scratch = Vips::Image.black(image.width, image.height)
        (intensity * 5).to_i.times do
          x = rand(image.width)
          # Would need drawing operations - simplified
        end

        image.composite2(dust_mask * 255, 'lighten')
      rescue
        image
      end

      def apply_vhs(image, intensity)
        # VHS effects: tracking lines, color bleed, noise
        result = apply_chromatic_aberration(image, intensity * 0.5)
        result = apply_color_bleed(result, intensity * 0.3)

        # Add horizontal noise bands
        noise = Vips::Image.gaussnoise(image.width, image.height, sigma: intensity * 30)
        result.composite2(noise.cast('uchar'), 'soft-light', opacity: intensity * 0.3)
      rescue
        image
      end

      def apply_glitch(image, intensity)
        # Digital glitch: slice and shift
        slices = (intensity * 10).to_i.clamp(1, 20)
        slice_height = image.height / slices

        result = image
        slices.times do |i|
          next unless rand < intensity * 0.5

          y = i * slice_height
          shift = (rand - 0.5) * intensity * 50

          slice = image.crop(0, y, image.width, [slice_height, image.height - y].min)
          # Would need composition - simplified
        end

        # Add RGB split
        apply_chromatic_aberration(result, intensity)
      rescue
        image
      end

      # ─────────────────────────────────────────────────────────────────────
      # Skin protection for teal/orange
      # ─────────────────────────────────────────────────────────────────────

      def protect_skin_tones(image, protection = 0.8)
        # Detect skin-like colors (simplified)
        r, g, b = image.bandsplit

        # Skin is roughly R > G > B with specific ratios
        skin_mask = (r.more(g) & g.more(b) & r.more(100) & r.less(250))

        # Return mask for blending
        skin_mask.ifthenelse(protection, 1.0)
      rescue
        1.0
      end

      def apply_teal_orange_protected(image, intensity)
        protection = protect_skin_tones(image, 0.8)

        r, g, b = image.bandsplit
        r_enhanced = r.linear([1 + 0.25 * intensity], [8 * intensity])
        g_balanced = g.linear([1 - 0.08 * intensity], [0])
        b_enhanced = b.linear([1 + 0.35 * intensity], [0])

        graded = Vips::Image.bandjoin([r_enhanced, g_balanced, b_enhanced])

        # Blend based on skin protection
        image * protection + graded * (1 - protection)
      rescue
        apply_teal_orange(image, intensity)
      end

      # ─────────────────────────────────────────────────────────────────────
      # Random effects for experimentation
      # ─────────────────────────────────────────────────────────────────────

      def apply_random_effects(image, count: 3, mode: :professional)
        available = mode == :experimental ? EFFECTS : EFFECTS.first(10)
        selected = available.sample(count)

        result = image
        selected.each do |effect|
          intensity = rand(0.3..0.8)
          result = apply_effect(result, effect, intensity)
        end

        result
      end

      # ─────────────────────────────────────────────────────────────────────
      # Recipe system for custom effect chains
      # ─────────────────────────────────────────────────────────────────────

      def apply_recipe(image, recipe)
        result = image

        recipe.each do |step|
          effect = step[:effect]&.to_sym
          intensity = step[:intensity] || 0.5
          params = step[:params] || {}

          result = apply_effect(result, effect, intensity)
        end

        result
      end
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
