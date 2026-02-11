# frozen_string_literal: true

module MASTER
  # RepLigen Bridge - Interface to AI media generation pipeline
  # Based on repligen.rb WILD_CHAIN model catalog
  # Provides access to image, video, and enhancement models
  module RepLigenBridge
    extend self

    # Model catalog from repligen's WILD_CHAIN
    WILD_CHAIN = {
      image_gen: [
        { model: "black-forest-labs/flux-pro", name: "Flux Pro" },
        { model: "black-forest-labs/flux-dev", name: "Flux Dev" },
        { model: "stability-ai/sdxl", name: "SDXL" },
        { model: "ideogram-ai/ideogram-v2", name: "Ideogram V2" },
        { model: "recraft-ai/recraft-v3", name: "Recraft V3" }
      ],
      video_gen: [
        { model: "minimax/video-01", name: "Hailuo 2.3" },
        { model: "kwaivgi/kling-v2.5-turbo-pro", name: "Kling 2.5" },
        { model: "luma/ray-2", name: "Luma Ray 2" },
        { model: "wan-video/wan-2.5-i2v", name: "WAN 2.5" },
        { model: "openai/sora-2", name: "Sora 2" }
      ],
      enhance: [
        { model: "nightmareai/real-esrgan", name: "Real-ESRGAN 4x" },
        { model: "tencentarc/gfpgan", name: "GFPGAN Face" },
        { model: "sczhou/codeformer", name: "CodeFormer" },
        { model: "lucataco/clarity-upscaler", name: "Clarity 4x" }
      ],
      audio: [
        { model: "meta/musicgen", name: "MusicGen" },
        { model: "suno/bark", name: "Bark TTS" }
      ],
      transcribe: [
        { model: "openai/whisper", name: "Whisper" }
      ]
    }.freeze

    # Get all models for a category
    def models_for(category)
      WILD_CHAIN[category.to_sym] || []
    end

    # List all available categories
    def categories
      WILD_CHAIN.keys
    end

    # Generate image using Replicate API
    def generate_image(prompt:, model: nil)
      model_id = model || WILD_CHAIN[:image_gen].first[:model]
      
      return Result.err("Replicate not available") unless defined?(Replicate) && Replicate.available?
      
      Replicate.generate(prompt: prompt, model: model_id)
    end

    # Generate video using Replicate API
    def generate_video(prompt:, model: nil)
      model_id = model || WILD_CHAIN[:video_gen].first[:model]
      
      return Result.err("Replicate not available") unless defined?(Replicate) && Replicate.available?
      
      Replicate.generate(prompt: prompt, model: model_id)
    end

    # Enhance image using upscaling models
    def enhance_image(image_url:, model: nil)
      model_id = model || WILD_CHAIN[:enhance].first[:model]
      
      return Result.err("Replicate not available") unless defined?(Replicate) && Replicate.available?
      
      Replicate.generate(prompt: "", model: model_id, params: { image: image_url })
    end

    # Get model info
    def model_info(model_id)
      WILD_CHAIN.each do |category, models|
        models.each do |m|
          return { category: category, **m } if m[:model] == model_id
        end
      end
      nil
    end

    # List all models
    def all_models
      result = []
      WILD_CHAIN.each do |category, models|
        models.each do |m|
          result << { category: category, **m }
        end
      end
      result
    end
  end
end
