# frozen_string_literal: true

require_relative 'repligen/pipelines'

module MASTER
  module Bridges
    # Repligen Bridge - Interface to AI media generation pipeline
    # Based on repligen.rb WILD_CHAIN model catalog
    # Provides access to image, video, and enhancement models
    module RepligenBridge
      extend self

      # Model catalog - delegates to Replicate::MODELS for DRY
      def self.model_catalog
        @model_catalog ||= {
          image_gen: [
            { model: MASTER::Replicate::MODELS[:flux_pro], name: "Flux Pro" },
            { model: MASTER::Replicate::MODELS[:flux_dev], name: "Flux Dev" },
            { model: MASTER::Replicate::MODELS[:sdxl], name: "SDXL" },
            { model: MASTER::Replicate::MODELS[:ideogram_v2], name: "Ideogram V2" },
            { model: MASTER::Replicate::MODELS[:recraft_v3], name: "Recraft V3" }
          ],
          video_gen: [
            { model: MASTER::Replicate::MODELS[:hailuo], name: "Hailuo 2.3" },
            { model: MASTER::Replicate::MODELS[:kling], name: "Kling 2.5" },
            { model: MASTER::Replicate::MODELS[:luma_ray], name: "Luma Ray 2" },
            { model: MASTER::Replicate::MODELS[:wan], name: "WAN 2.5" },
            { model: MASTER::Replicate::MODELS[:sora], name: "Sora 2" }
          ],
          enhance: [
            { model: MASTER::Replicate::MODELS[:esrgan], name: "Real-ESRGAN 4x" },
            { model: MASTER::Replicate::MODELS[:gfpgan], name: "GFPGAN Face" },
            { model: MASTER::Replicate::MODELS[:codeformer], name: "CodeFormer" },
            { model: MASTER::Replicate::MODELS[:clarity], name: "Clarity 4x" }
          ],
          audio: [
            { model: MASTER::Replicate::MODELS[:musicgen], name: "MusicGen" },
            { model: MASTER::Replicate::MODELS[:bark], name: "Bark TTS" }
          ],
          transcribe: [
            { model: MASTER::Replicate::MODELS[:whisper], name: "Whisper" }
          ]
        }.freeze
      end

      # Get all models for a category
      def models_for(category)
        RepligenBridge.model_catalog[category.to_sym] || []
      end

      # List all available categories
      def categories
        RepligenBridge.model_catalog.keys
      end

      # Generate image using Replicate API
      def generate_image(prompt:, model: nil)
        model_id = model || RepligenBridge.model_catalog[:image_gen].first[:model]

        return Result.err("Replicate not available.") unless defined?(Replicate) && Replicate.available?

        Replicate.generate(prompt: prompt, model: model_id)
      end

      # Generate video using Replicate API
      def generate_video(prompt:, model: nil)
        model_id = model || RepligenBridge.model_catalog[:video_gen].first[:model]

        return Result.err("Replicate not available.") unless defined?(Replicate) && Replicate.available?

        Replicate.run(model_id: model_id, input: { prompt: prompt })
      end

      # Enhance image using upscaling models
      def enhance_image(image_url:, model: nil)
        model_id = model || RepligenBridge.model_catalog[:enhance].first[:model]

        return Result.err("Replicate not available.") unless defined?(Replicate) && Replicate.available?

        Replicate.run(model_id: model_id, input: { image: image_url })
      end

      # Get model info
      def model_info(model_id)
        RepligenBridge.model_catalog.each do |category, models|
          models.each do |m|
            return { category: category, **m } if m[:model] == model_id
          end
        end
        nil
      end

      # List all models
      def all_models
        result = []
        RepligenBridge.model_catalog.each do |category, models|
          models.each do |m|
            result << { category: category, **m }
          end
        end
        result
      end

      # Catwalk styles and lighting constants
      CATWALK_STYLES = %w[haute_couture streetwear avant_garde minimalist sportswear editorial fantasy cyberpunk].freeze
      CATWALK_LIGHTING = %w[runway studio natural dramatic neon golden cinematic].freeze

      # Wild chain - random creative pipeline combos
      def wild_chain(steps: 3, seed: nil)
        rng = seed ? Random.new(seed) : Random.new

        chain = []
        steps.times do
          category = [:image_gen, :enhance, :video_gen].sample(random: rng)
          models = RepligenBridge.model_catalog[category]

          next if models.nil? || models.empty?

          model = models.sample(random: rng)
          chain << {
            step: chain.length + 1,
            category: category,
            model: model[:model],
            name: model[:name]
          }
        end

        Result.ok(chain)
      end
    end
  end
end
