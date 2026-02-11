# frozen_string_literal: true

module MASTER
  # Repligen Bridge - Interface to AI media generation pipeline
  # References canonical model registry from Replicate module
  # Provides access to image, video, and enhancement models
  module RepligenBridge
    extend self

    # Model catalog - references Replicate::MODELS for canonical source
    WILD_CHAIN = {
      image_gen: [
        { model: Replicate::MODELS[:flux], name: "Flux 1.1 Pro" },
        { model: Replicate::MODELS[:flux2], name: "Flux 2" },
        { model: Replicate::MODELS[:sdxl], name: "SDXL" },
        { model: Replicate::MODELS[:ideogram], name: "Ideogram V2" },
        { model: Replicate::MODELS[:recraft], name: "Recraft V3" }
      ],
      video_gen: [
        { model: Replicate::VIDEO_MODELS[:hailuo], name: "Hailuo 2.3" },
        { model: Replicate::VIDEO_MODELS[:kling], name: "Kling 2.5" },
        { model: Replicate::VIDEO_MODELS[:ray], name: "Luma Ray 2" },
        { model: Replicate::VIDEO_MODELS[:wan], name: "WAN 2.5" }
      ],
      enhance: [
        { model: Replicate::ENHANCE_MODELS[:esrgan], name: "Real-ESRGAN 4x" },
        { model: Replicate::ENHANCE_MODELS[:gfpgan], name: "GFPGAN Face" },
        { model: Replicate::ENHANCE_MODELS[:codeformer], name: "CodeFormer" },
        { model: "lucataco/clarity-upscaler", name: "Clarity 4x" }
      ],
      audio: [
        { model: Replicate::AUDIO_MODELS[:musicgen], name: "MusicGen" },
        { model: Replicate::AUDIO_MODELS[:bark], name: "Bark TTS" }
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

    # Catwalk styles and lighting constants
    CATWALK_STYLES = %w[haute_couture streetwear avant_garde minimalist sportswear editorial fantasy cyberpunk].freeze
    CATWALK_LIGHTING = %w[runway studio natural dramatic neon golden cinematic].freeze

    # Wild chain - random creative pipeline combos
    def wild_chain(steps: 3, seed: nil)
      rng = seed ? Random.new(seed) : Random.new
      
      chain = []
      steps.times do
        # Randomly pick a category (prefer image gen and enhance)
        category = [:image_gen, :enhance, :video_gen].sample(random: rng)
        models = WILD_CHAIN[category]
        
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

    # Execute a multi-model pipeline sequentially
    def execute_chain(chain)
      return Result.err("Chain cannot be empty") if chain.nil? || chain.empty?
      return Result.err("Replicate not available") unless defined?(Replicate) && Replicate.available?
      
      results = []
      current_output = nil
      
      chain.each_with_index do |step, idx|
        params = {}
        
        # If not first step and previous output exists, use it as input
        if idx > 0 && current_output
          params[:image] = current_output if step[:category] == :enhance
          params[:init_image] = current_output if step[:category] == :image_gen
        end
        
        # Execute step
        result = Replicate.generate(
          prompt: step[:prompt] || "",
          model: step[:model],
          params: params
        )
        
        return result if result.err?
        
        current_output = result.ok
        results << {
          step: idx + 1,
          model: step[:name],
          output: current_output
        }
      end
      
      Result.ok(results)
    end

    # Generate catwalk fashion image
    def generate_catwalk(prompt:, style: nil, lighting: nil, model: nil)
      style ||= CATWALK_STYLES.sample
      lighting ||= CATWALK_LIGHTING.sample
      
      return Result.err("Unknown style: #{style}") unless CATWALK_STYLES.include?(style.to_s)
      return Result.err("Unknown lighting: #{lighting}") unless CATWALK_LIGHTING.include?(lighting.to_s)
      
      full_prompt = "fashion photography, #{style} style, #{lighting} lighting, #{prompt}"
      model_id = model || WILD_CHAIN[:image_gen].first[:model]
      
      return Result.err("Replicate not available") unless defined?(Replicate) && Replicate.available?
      
      Replicate.generate(
        prompt: full_prompt,
        model: model_id,
        params: { style: style, lighting: lighting }
      )
    end

    # Search models by keyword
    def search_models(query)
      query_lower = query.to_s.downcase
      matches = []
      
      WILD_CHAIN.each do |category, models|
        models.each do |m|
          if m[:name].downcase.include?(query_lower) || m[:model].downcase.include?(query_lower)
            matches << { category: category, **m }
          end
        end
      end
      
      Result.ok(matches)
    end

    # Train LoRA wrapper
    def train_lora(training_data:, trigger_word:, model: "ostris/flux-dev-lora-trainer")
      return Result.err("Replicate not available") unless defined?(Replicate) && Replicate.available?
      return Result.err("Training data cannot be empty") if training_data.nil? || training_data.empty?
      return Result.err("Trigger word required") if trigger_word.nil? || trigger_word.empty?
      
      Replicate.generate(
        prompt: "",
        model: model,
        params: {
          input_images: training_data,
          trigger_word: trigger_word,
          steps: 1000,
          learning_rate: 0.0004
        }
      )
    end
  end
end
