# frozen_string_literal: true

require 'fileutils'
require 'yaml'

module MASTER
  # Cinematic - AI-powered cinematic pipeline and color grading
  # Chains Replicate models to create film-quality image/video transformations
  module Cinematic
    extend self

    # Cinematic presets - film looks and color grades
    PRESETS = {
      'blade-runner' => {
        description: 'Cyberpunk aesthetic: neon, rain, cyan/orange split tones',
        models: ['stability-ai/sdxl', 'tencentarc/gfpgan'],
        params: { guidance_scale: 12.0, strength: 0.6 }
      },
      'wes-anderson' => {
        description: 'Symmetrical, pastel palette, centered compositions',
        models: ['stability-ai/sdxl'],
        params: { guidance_scale: 8.0, strength: 0.5 }
      },
      'noir' => {
        description: 'High contrast black and white, dramatic shadows',
        models: ['stability-ai/sdxl'],
        params: { guidance_scale: 10.0, strength: 0.7 }
      },
      'golden-hour' => {
        description: 'Warm, soft, glowing light',
        models: ['stability-ai/sdxl'],
        params: { guidance_scale: 9.0, strength: 0.5 }
      },
      'teal-orange' => {
        description: 'Hollywood blockbuster: teal shadows, orange highlights',
        models: ['stability-ai/sdxl'],
        params: { guidance_scale: 11.0, strength: 0.6 }
      }
    }.freeze

    # Pipeline builder class
    class Pipeline
      attr_reader :stages

      def initialize
        @stages = []
      end

      # Chain a model into the pipeline
      def chain(model_id, params = {})
        @stages << {
          model: model_id,
          params: params
        }
        self  # Return self for chaining
      end

      # Execute pipeline on input
      def execute(input, save_intermediates: false)
        return Result.err("Empty pipeline") if @stages.empty?

        results = []
        current_output = input

        @stages.each_with_index do |stage, idx|
          puts "  Stage #{idx + 1}/#{@stages.size}: #{stage[:model]}"

          # Merge params with current output
          stage_input = detect_input_type(current_output, stage[:model])
          combined_params = stage[:params].merge(stage_input)

          # Run model via Replicate
          result = Replicate.run(
            model_id: stage[:model],
            input: {},
            params: combined_params
          )

          return result if result.err?

          # Extract output
          current_output = extract_output(result.value[:output])

          # Save intermediate if requested
          if save_intermediates
            save_intermediate(current_output, idx, stage[:model])
          end

          results << {
            stage: idx,
            model: stage[:model],
            output: current_output
          }
        end

        Result.ok({
          final: current_output,
          stages: results
        })
      end

      # Save pipeline as preset
      def save_preset(name:, description:, tags: [])
        preset = {
          'name' => name,
          'description' => description,
          'tags' => tags,
          'stages' => @stages.map { |s| { 'model' => s[:model], 'params' => s[:params] } },
          'created_at' => Time.now.utc.iso8601
        }

        # Ensure pipelines directory exists
        pipelines_dir = File.join(Paths.data, 'pipelines')
        FileUtils.mkdir_p(pipelines_dir)

        # Save to filesystem
        filename = name.downcase.gsub(/[^a-z0-9]+/, '-') + '.yml'
        path = File.join(pipelines_dir, filename)
        File.write(path, YAML.dump(preset))

        # Index in Weaviate if available
        if Weaviate.available?
          embedding = generate_embedding(description)
          Weaviate.index('Pipeline', preset.merge('vector' => embedding)) if embedding
        end

        Result.ok({ path: path })
      rescue => e
        $stderr.puts "Cinematic: save preset error: #{e.class} - #{e.message}"
        Result.err("Failed to save preset: #{e.message}")
      end

      # Load preset by name
      def self.load(name)
        pipelines_dir = File.join(Paths.data, 'pipelines')
        filename = name.downcase.gsub(/[^a-z0-9]+/, '-') + '.yml'
        path = File.join(pipelines_dir, filename)

        return Result.err("Preset not found: #{name}") unless File.exist?(path)

        preset = YAML.safe_load_file(path, permitted_classes: [Symbol])
        pipeline = new

        preset['stages'].each do |stage|
          pipeline.chain(stage['model'], stage['params'] || {})
        end

        Result.ok(pipeline)
      rescue => e
        $stderr.puts "Cinematic: load preset error: #{e.class} - #{e.message}"
        Result.err("Failed to load preset: #{e.message}")
      end

      # Generate random creative pipeline
      def self.random(length: 5, category: :all)
        pipeline = new
        models = discover_models(category)

        return Result.err("No models found") if models.empty?

        length.times do
          model = models.sample
          params = generate_creative_params
          pipeline.chain(model, params)
        end

        Result.ok(pipeline)
      end

      private

      def detect_input_type(output, model_id)
        # Detect if output is image, video, or text
        if output.is_a?(String)
          if output.match?(/\.(jpg|jpeg|png|webp)$/i)
            { 'image' => output }
          elsif output.match?(/\.(mp4|mov|avi)$/i)
            { 'video' => output }
          else
            { 'prompt' => output }
          end
        elsif output.is_a?(Array)
          { 'image' => output.first }
        else
          { 'input' => output }
        end
      end

      def extract_output(result_output)
        # Extract URL or data from Replicate response
        if result_output.is_a?(Array)
          result_output.first
        elsif result_output.is_a?(String)
          result_output
        else
          result_output
        end
      end

      def save_intermediate(output, stage_idx, model_id)
        return unless output.is_a?(String) && output.match?(/^https?:/)

        model_name = model_id.split('/').last.gsub(/[^a-z0-9]/i, '_')
        filename = "stage_#{stage_idx}_#{model_name}.png"
        
        intermediate_dir = File.join(Paths.var, 'pipeline')
        FileUtils.mkdir_p(intermediate_dir)
        
        path = File.join(intermediate_dir, filename)
        Replicate.download_file(output, path)
      rescue => e
        $stderr.puts "Cinematic: save_intermediate failed: #{e.message}"
        # Intermediate saves are optional, continue execution
      end

      def generate_embedding(text)
        return nil unless defined?(LLM) && LLM.configured?
        
        # Use OpenRouter for embeddings if available
        # For now, return nil - embeddings can be added later
        nil
      end

      def self.discover_models(category)
        # Model list based on repligen's WILD_CHAIN
        # Updated with current best models for each category
        case category
        when :image
          [
            'black-forest-labs/flux-pro',
            'black-forest-labs/flux-dev',
            'stability-ai/sdxl',
            'ideogram-ai/ideogram-v2',
            'recraft-ai/recraft-v3'
          ]
        when :video
          [
            'minimax/video-01',      # Hailuo 2.3
            'kwaivgi/kling-v2.5-turbo-pro',
            'luma/ray-2',
            'wan-video/wan-2.5-i2v',
            'openai/sora-2'
          ]
        when :enhance
          [
            'nightmareai/real-esrgan',
            'tencentarc/gfpgan',
            'sczhou/codeformer',
            'lucataco/clarity-upscaler'
          ]
        when :audio
          [
            'meta/musicgen',
            'suno/bark'
          ]
        when :transcribe
          ['openai/whisper']
        when :color
          ['stability-ai/sdxl']
        else
          # All models combined
          [
            'black-forest-labs/flux-pro',
            'black-forest-labs/flux-dev',
            'stability-ai/sdxl',
            'ideogram-ai/ideogram-v2',
            'recraft-ai/recraft-v3',
            'minimax/video-01',
            'kwaivgi/kling-v2.5-turbo-pro',
            'nightmareai/real-esrgan',
            'tencentarc/gfpgan',
            'sczhou/codeformer',
            'lucataco/clarity-upscaler',
            'meta/musicgen',
            'suno/bark',
            'openai/whisper'
          ]
        end
      end

      def self.generate_creative_params
        {
          'seed' => rand(1..999999),
          'guidance_scale' => rand(5.0..15.0).round(1),
          'num_inference_steps' => rand(20..50)
        }
      end
    end

    # Apply a named preset
    def apply_preset(input, preset_name)
      preset = PRESETS[preset_name]
      return Result.err("Unknown preset: #{preset_name}") unless preset

      pipeline = Pipeline.new
      preset[:models].each do |model|
        pipeline.chain(model, preset[:params])
      end

      pipeline.execute(input, save_intermediates: true)
    end

    # Discover new styles via random exploration
    def discover_style(input, samples: 10)
      puts "Discovering new cinematic styles..."

      results = []
      samples.times do |i|
        puts "  Sample #{i + 1}/#{samples}"

        # Random pipeline 3-6 stages long
        pipeline_result = Pipeline.random(length: rand(3..6), category: :image)
        next if pipeline_result.err?

        pipeline = pipeline_result.value
        result = pipeline.execute(input)
        next if result.err?

        score = score_aesthetic(result.value)
        results << {
          pipeline: pipeline,
          result: result.value,
          score: score
        }
      end

      return Result.err("No successful pipelines generated") if results.empty?

      # Sort by score and return top results
      top = results.sort_by { |r| -r[:score] }.first(3)

      Result.ok({ discoveries: top })
    end

    # List available presets
    def list_presets
      builtin = PRESETS.keys.map do |name|
        { name: name, description: PRESETS[name][:description], source: 'builtin' }
      end

      # Load custom presets from disk
      pipelines_dir = File.join(Paths.data, 'pipelines')
      custom = if Dir.exist?(pipelines_dir)
        Dir.glob(File.join(pipelines_dir, '*.yml')).map do |path|
          preset = YAML.safe_load_file(path, permitted_classes: [Symbol])
          { 
            name: preset['name'], 
            description: preset['description'], 
            source: 'custom' 
          }
        end
      else
        []
      end

      Result.ok({ presets: builtin + custom })
    end

    private

    def score_aesthetic(result)
      # Simple placeholder scoring
      # In production, could use LAION aesthetic predictor or similar
      rand(0.5..1.0)
    end
  end
end
