# frozen_string_literal: true

require_relative 'postpro/vips_effects'

module MASTER
  module Bridges
    # Postpro Bridge - The Cinematic Emotion Engine
    # Analog film emulation and psychological color grading
    # Applied as final layer on all Replicate outputs
    module PostproBridge
      extend self

      # Film stock emotional parameters
      STOCKS = {
        kodak_portra: {
          grain: 15, gamma: 0.65, toe: 0.10, shoulder: 0.88, lift: 0.05,
          feeling: "Warmth, intimacy, skin-friendly pastels"
        },
        kodak_vision3_50d: {
          grain: 8, gamma: 0.63, toe: 0.08, shoulder: 0.92, lift: 0.02,
          feeling: "Daylight clarity, natural saturation, crisp shadows"
        },
        kodak_vision3_500t: {
          grain: 20, gamma: 0.65, toe: 0.12, shoulder: 0.88, lift: 0.08, blue_shift: 0.15,
          feeling: "Tungsten warmth, night atmosphere, moody interiors"
        },
        fuji_velvia: {
          grain: 8, gamma: 0.75, toe: 0.05, shoulder: 0.95, lift: 0.03,
          feeling: "Vivid saturation, punchy contrast, landscape drama"
        },
        tri_x: {
          grain: 25, gamma: 0.70, toe: 0.15, shoulder: 0.80, lift: 0.12,
          feeling: "Gritty documentary, street photography, honest imperfection"
        },
        cinestill_800t: {
          grain: 22, gamma: 0.68, toe: 0.14, shoulder: 0.85, lift: 0.10, halation: 0.8,
          feeling: "Neon halation, urban night, nostalgic glow"
        },
        ektachrome_100: {
          grain: 10, gamma: 0.72, toe: 0.06, shoulder: 0.94, lift: 0.04,
          feeling: "Slide film transparency, rich blues, vintage travel"
        }
      }.freeze

      PRINTS = {
        print_2383: { contrast: 1.1, saturation: 1.15, feeling: "Standard cinema projection" },
        print_3510: { contrast: 1.05, saturation: 1.0, feeling: "Subtle archival look" },
        vision_premiere: { contrast: 1.2, saturation: 1.1, feeling: "Modern theatrical release" }
      }.freeze

      LENSES = {
        zeiss_planar: {
          micro_contrast: 0.4, flare: 0.1, vignette: 0.15,
          feeling: "Clinical sharpness with organic falloff"
        },
        helios_44: {
          swirl_bokeh: 0.6, chromatic_aberration: 0.08, softness: 0.2,
          feeling: "Soviet swirl, dreamy portraits, psychedelic edges"
        },
        leica_summilux: {
          glow: 0.3, micro_contrast: 0.5, vignette: 0.08,
          feeling: "Romantic highlight bloom, legendary rendering"
        },
        cooke_panchro: {
          warmth: 0.15, softness: 0.1, skin_tone: 0.9,
          feeling: "Hollywood golden age, flattering skin, cinematic warmth"
        },
        anamorphic_kowa: {
          flare: 0.7, oval_bokeh: true, squeeze: 2.0,
          feeling: "Widescreen epic, horizontal streaks, theatrical scope"
        }
      }.freeze

      PRESETS = {
        portrait: {
          stock: :kodak_portra, print: :print_2383, lens: :zeiss_planar,
          halation: 0.3, grain: 0.4, tint: [255, 250, 245],
          feeling: "Intimacy, warmth, human connection"
        },
        blockbuster: {
          stock: :kodak_vision3_500t, print: :vision_premiere, lens: :anamorphic_kowa,
          halation: 0.7, grain: 0.5, teal_orange: 1.1,
          feeling: "Awe, spectacle, larger than life"
        },
        street: {
          stock: :tri_x, print: :print_3510, lens: :helios_44,
          grain: 0.9, desaturate: 0.8,
          feeling: "Immediacy, tension, documentary truth"
        },
        dream: {
          stock: :ektachrome_100, print: :print_2383, lens: :leica_summilux,
          halation: 0.5, grain: 0.3, shadow_lift: 0.25,
          feeling: "Memory, reverie, subjective inner world"
        },
        neon_night: {
          stock: :cinestill_800t, print: :vision_premiere, lens: :cooke_panchro,
          halation: 0.9, grain: 0.6,
          feeling: "Urban nocturne, neon glow, nostalgic future"
        },
        horror: {
          stock: :tri_x, print: :print_3510, lens: :helios_44,
          grain: 1.0, desaturate: 0.9, green_push: 0.15, contrast: 1.3,
          feeling: "Dread, unease, unsettling atmosphere"
        },
        golden_age: {
          stock: :kodak_vision3_50d, print: :print_2383, lens: :cooke_panchro,
          halation: 0.4, grain: 0.3, warmth: 0.2,
          feeling: "Classic Hollywood glamour, timeless elegance"
        },
        indie: {
          stock: :kodak_portra, print: :print_3510, lens: :helios_44,
          grain: 0.7, shadow_lift: 0.15,
          feeling: "Authentic, unpolished, genuine humanity"
        }
      }.freeze

      EFFECTS = %i[
        grain halation vignette chromatic_aberration lens_flare
        light_leak dust_scratches gate_weave color_bleed
        teal_orange bleach_bypass cross_process day_for_night
        infrared sepia cyanotype shadow_lift highlight_roll
      ].freeze

      # Replicate-backed enhancement operations
      OPERATIONS = {
        upscale: { name: "Upscale 4x", models: ["nightmareai/real-esrgan", "lucataco/clarity-upscaler"] },
        face_restore: { name: "Face Restoration", models: ["tencentarc/gfpgan", "sczhou/codeformer"] }
      }.freeze

      # --- Main entry points ---

      def apply_preset(path, preset: :portrait)
        return Result.err("File not found") unless File.exist?(path)
        return Result.err("ruby-vips not available") unless vips_available?

        config = PRESETS[preset.to_sym]
        return Result.err("Unknown preset: #{preset}") unless config

        image = load_image(path)
        return Result.err("Failed to load image") unless image

        image = apply_stock(image, config[:stock]) if config[:stock]
        image = apply_halation(image, config[:halation]) if config[:halation]
        image = apply_grain(image, config[:grain], config[:stock]) if config[:grain]
        image = apply_teal_orange(image, config[:teal_orange]) if config[:teal_orange]
        image = apply_shadow_lift(image, config[:shadow_lift]) if config[:shadow_lift]
        image = apply_desaturate(image, config[:desaturate]) if config[:desaturate]
        image = apply_tint(image, config[:tint]) if config[:tint]
        image = apply_lens(image, config[:lens]) if config[:lens]

        output_path = generate_output_path(path, preset)
        save_image(image, output_path)
        Result.ok(output_path)
      rescue StandardError => e
        Result.err("Preset failed: #{e.message}")
      end

      def apply_random(path, count: 3)
        return Result.err("File not found") unless File.exist?(path)
        return Result.err("ruby-vips not available") unless vips_available?

        image = load_image(path)
        return Result.err("Failed to load image") unless image

        effects = EFFECTS.sample(count)
        effects.each do |effect|
          intensity = rand(0.3..0.8)
          image = apply_effect(image, effect, intensity)
        end

        output_path = generate_output_path(path, :random)
        save_image(image, output_path)
        Result.ok({ path: output_path, effects: effects })
      rescue StandardError => e
        Result.err("Random effects failed: #{e.message}")
      end

      def css_filter(preset: :portrait)
        config = PRESETS[preset.to_sym] || PRESETS[:portrait]
        stock = STOCKS[config[:stock]] || {}

        filters = []
        filters << "contrast(#{1 + (stock[:gamma] || 0.65) * 0.2})"
        filters << "saturate(#{config[:teal_orange] || 1.0})"
        filters << "sepia(#{config[:warmth] || 0})" if config[:warmth]
        filters << "grayscale(#{config[:desaturate] || 0})" if config[:desaturate]
        filters.join(" ")
      end

      def list_presets
        PRESETS.map { |name, config| "  #{name}: #{config[:feeling]}" }.join("\n")
      end

      def list_stocks
        STOCKS.map { |name, config| "  #{name}: #{config[:feeling]}" }.join("\n")
      end

      def list_lenses
        LENSES.map { |name, config| "  #{name}: #{config[:feeling]}" }.join("\n")
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

      # --- Replicate-backed operations ---

      def enhance(image_url:, operation:, params: {})
        return Result.err("Unknown operation: #{operation}") unless OPERATIONS.key?(operation.to_sym)

        op = OPERATIONS[operation.to_sym]
        return Result.err("Replicate not available") unless defined?(Replicate) && Replicate.available?

        Replicate.generate(prompt: "", model: op[:models].first, params: { image: image_url }.merge(params))
      end

      def upscale(image_url:, scale: 4, model: nil)
        model_id = model || OPERATIONS[:upscale][:models].first
        return Result.err("Replicate not available") unless defined?(Replicate) && Replicate.available?

        Replicate.generate(prompt: "", model: model_id, params: { image: image_url, scale: scale })
      end

      def restore_face(image_url:, model: nil)
        model_id = model || OPERATIONS[:face_restore][:models].first
        return Result.err("Replicate not available") unless defined?(Replicate) && Replicate.available?

        Replicate.generate(prompt: "", model: model_id, params: { image: image_url })
      end

      def operations
        OPERATIONS.map { |key, op| { id: key, name: op[:name], models: op[:models] } }
      end

      def vips_available?
        @vips_available ||= begin
          require "vips"
          true
        rescue LoadError
          false
        end
      end
    end
  end
end
