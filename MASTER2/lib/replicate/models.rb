# frozen_string_literal: true

module MASTER
  module Replicate
    # Models - model definitions and lookups
    module Models
      MODELS = {
        # Image generation
        flux:         "black-forest-labs/flux-1.1-pro",
        flux_pro:     "black-forest-labs/flux-pro",
        flux_dev:     "black-forest-labs/flux-dev",
        sdxl:         "stability-ai/sdxl",
        kandinsky:    "ai-forever/kandinsky-2.2",
        ideogram_v2:  "ideogram-ai/ideogram-v2",
        recraft_v3:   "recraft-ai/recraft-v3",

        # Upscaling
        esrgan:       "nightmareai/real-esrgan",
        gfpgan:       "tencentarc/gfpgan",
        codeformer:   "sczhou/codeformer",
        clarity:      "lucataco/clarity-upscaler",

        # Video generation
        svd:          "stability-ai/stable-video-diffusion",
        hailuo:       "minimax/video-01",
        kling:        "kwaivgi/kling-v2.5-turbo-pro",
        luma_ray:     "luma/ray-2",
        wan:          "wan-video/wan-2.5-i2v",
        sora:         "openai/sora-2",

        # Audio
        musicgen:     "meta/musicgen",
        bark:         "suno/bark",

        # Transcription
        whisper:      "openai/whisper",

        # Captioning
        blip:         "salesforce/blip",

        # 3D
        shap_e:       "openai/shap-e"
      }.freeze

      MODEL_CATEGORIES = {
        image: [:flux, :flux_pro, :flux_dev, :sdxl, :kandinsky, :ideogram_v2, :recraft_v3],
        video: [:svd, :hailuo, :kling, :luma_ray, :wan, :sora],
        upscale: [:esrgan, :gfpgan, :codeformer, :clarity],
        audio: [:musicgen, :bark],
        transcribe: [:whisper],
        caption: [:blip],
        threed: [:shap_e]
      }.freeze

      DEFAULT_MODEL = :flux

      module_function

      # Lookup model ID by symbol name
      def model_id(name)
        model = MODELS[name.to_sym]
        raise ArgumentError, "Unknown model: #{name}" unless model
        model
      end

      # Get all models for a category
      def models_for(category)
        model_names = MODEL_CATEGORIES[category.to_sym]
        return [] unless model_names

        model_names.map do |name|
          { name: name, id: MODELS[name] }
        end
      end
    end
  end
end
