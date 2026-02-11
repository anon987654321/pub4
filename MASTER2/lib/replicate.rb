# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'
require_relative 'timeouts'

module MASTER
  # Replicate - Image generation via Replicate API
  module Replicate
    extend self

    API_URL = 'https://api.replicate.com/v1/predictions'

    MODELS = {
      flux:      'black-forest-labs/flux-1.1-pro',
      sdxl:      'stability-ai/sdxl',
      kandinsky: 'ai-forever/kandinsky-2.2'
    }.freeze

    DEFAULT_MODEL = :flux

    class << self
      def api_key
        ENV['REPLICATE_API_KEY']
      end

      def available?
        !api_key.nil? && !api_key.empty?
      end

      def generate(prompt:, model: DEFAULT_MODEL, params: {})
        return Result.err("REPLICATE_API_KEY not set") unless available?

        model_id = MODELS[model.to_sym] || MODELS[DEFAULT_MODEL]

        input = { prompt: prompt }.merge(params)

        # Create prediction
        prediction = create_prediction(model_id, input)
        return Result.err("Failed to create prediction: #{prediction[:error]}") if prediction[:error]

        # Poll for completion
        result = wait_for_completion(prediction[:id])
        return Result.err("Generation failed: #{result[:error]}") if result[:error]

        Result.ok({
          id: result[:id],
          urls: result[:output],
          model: model_id,
          prompt: prompt
        })
      end

      def upscale(image_url:, scale: 4)
        return Result.err("REPLICATE_API_TOKEN not set") unless available?

        model_id = 'nightmareai/real-esrgan'
        input = { image: image_url, scale: scale }

        prediction = create_prediction(model_id, input)
        return Result.err("Failed: #{prediction[:error]}") if prediction[:error]

        result = wait_for_completion(prediction[:id])
        return Result.err("Upscale failed: #{result[:error]}") if result[:error]

        Result.ok({ url: result[:output], scale: scale })
      end

      def describe(image_url:)
        return Result.err("REPLICATE_API_TOKEN not set") unless available?

        model_id = 'salesforce/blip'
        input = { image: image_url }

        prediction = create_prediction(model_id, input)
        return Result.err("Failed: #{prediction[:error]}") if prediction[:error]

        result = wait_for_completion(prediction[:id])
        return Result.err("Describe failed: #{result[:error]}") if result[:error]

        Result.ok({ caption: result[:output] })
      end

      # Generic model runner - supports any Replicate model
      def run(model_id:, input:, params: {})
        return Result.err("REPLICATE_API_KEY not set") unless available?

        combined_input = input.merge(params)

        prediction = create_prediction(model_id, input: combined_input)
        return Result.err("Failed to create prediction: #{prediction[:error]}") if prediction[:error]

        result = wait_for_completion(prediction[:id])
        return Result.err("Model run failed: #{result[:error]}") if result[:error]

        Result.ok({
          id: result[:id],
          output: result[:output],
          model: model_id
        })
      end

      # Download file from URL to local path
      def download_file(url, path)
        uri = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')
        
        response = http.get(uri.path)
        return false unless response.is_a?(Net::HTTPSuccess)
        
        FileUtils.mkdir_p(File.dirname(path))
        File.binwrite(path, response.body)
        true
      rescue => e
        $stderr.puts "Replicate: download_file failed for #{url}: #{e.message}"
        false
      end

      private

      def create_prediction(model_version_or_id, input: nil, version: nil)
        # Support both old signature (model_version, input) and new signature with named params
        actual_input = input || model_version_or_id.is_a?(Hash) ? {} : model_version_or_id
        actual_version = version || (model_version_or_id.is_a?(String) ? model_version_or_id : nil)
        
        uri = URI(API_URL)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = Timeouts::HTTP_OPEN_TIMEOUT
        http.read_timeout = Timeouts::HTTP_READ_TIMEOUT

        request = Net::HTTP::Post.new(uri)
        request['Authorization'] = "Bearer #{api_key}"
        request['Content-Type'] = 'application/json'
        
        body = { input: actual_input }
        body[:version] = actual_version if actual_version
        request.body = body.to_json

        response = http.request(request)
        data = JSON.parse(response.body, symbolize_names: true)

        if data[:id]
          { id: data[:id] }
        else
          { error: data[:detail] || 'Unknown error' }
        end
      rescue Net::OpenTimeout, Net::ReadTimeout
        { error: 'Request timed out' }
      rescue => e
        $stderr.puts "Replicate: create_prediction error: #{e.class} - #{e.message}"
        { error: e.message }
      end

      def wait_for_completion(id, timeout: Timeouts::REPLICATE_TIMEOUT)
        uri = URI("#{API_URL}/#{id}")
        start_time = Time.now
        max_polls = (timeout / Timeouts::POLL_INTERVAL).to_i  # Calculate max polls based on timeout

        max_polls.times do
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.open_timeout = Timeouts::HTTP_OPEN_TIMEOUT
          http.read_timeout = Timeouts::HTTP_READ_TIMEOUT

          request = Net::HTTP::Get.new(uri)
          request['Authorization'] = "Bearer #{api_key}"

          response = http.request(request)
          data = JSON.parse(response.body, symbolize_names: true)

          case data[:status]
          when 'succeeded'
            return { id: id, output: data[:output] }
          when 'failed', 'canceled'
            return { error: data[:error] || 'Generation failed' }
          when 'processing', 'starting'
            sleep Timeouts::POLL_INTERVAL
          else
            return { error: "Unknown status: #{data[:status]}" }
          end

          return { error: 'Timeout waiting for generation' } if Time.now - start_time > timeout
        end

        { error: 'Max polls exceeded' }
      rescue Net::OpenTimeout, Net::ReadTimeout
        { error: 'Poll request timed out' }
      rescue => e
        $stderr.puts "Replicate: wait_for_completion error: #{e.class} - #{e.message}"
        { error: e.message }
      end
    end
  end

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

  # PostPro Bridge - Post-processing and enhancement utilities
  # Provides image and video enhancement capabilities
  module PostProBridge
    extend self

    # Enhancement operations
    OPERATIONS = {
      upscale: {
        name: "Upscale 4x",
        models: ["nightmareai/real-esrgan", "lucataco/clarity-upscaler"]
      },
      face_restore: {
        name: "Face Restoration",
        models: ["tencentarc/gfpgan", "sczhou/codeformer"]
      },
      denoise: {
        name: "Denoise",
        description: "Remove noise from images"
      },
      color_grade: {
        name: "Color Grading",
        description: "Apply color grading presets"
      },
      sharpen: {
        name: "Sharpen",
        description: "Enhance image sharpness"
      }
    }.freeze

    # Apply enhancement to image
    def enhance(image_url:, operation:, params: {})
      return Result.err("Unknown operation: #{operation}") unless OPERATIONS.key?(operation.to_sym)
      
      op = OPERATIONS[operation.to_sym]
      
      if op[:models]
        # Use Replicate model
        model = op[:models].first
        return Result.err("Replicate not available") unless defined?(Replicate) && Replicate.available?
        
        Replicate.generate(
          prompt: "",
          model: model,
          params: { image: image_url }.merge(params)
        )
      else
        # Local processing (placeholder)
        Result.err("Local processing not yet implemented for #{operation}")
      end
    end

    # Batch enhance multiple images
    def batch_enhance(image_urls:, operation:, params: {})
      results = []
      
      image_urls.each do |url|
        result = enhance(image_url: url, operation: operation, params: params)
        results << { url: url, result: result }
      end
      
      Result.ok(results)
    end

    # List available operations
    def operations
      OPERATIONS.map do |key, op|
        {
          id: key,
          name: op[:name],
          description: op[:description] || op[:name],
          models: op[:models]
        }
      end
    end

    # Upscale shortcut
    def upscale(image_url:, scale: 4, model: nil)
      model_id = model || OPERATIONS[:upscale][:models].first
      
      return Result.err("Replicate not available") unless defined?(Replicate) && Replicate.available?
      
      Replicate.generate(
        prompt: "",
        model: model_id,
        params: { image: image_url, scale: scale }
      )
    end

    # Face restoration shortcut
    def restore_face(image_url:, model: nil)
      model_id = model || OPERATIONS[:face_restore][:models].first
      
      return Result.err("Replicate not available") unless defined?(Replicate) && Replicate.available?
      
      Replicate.generate(
        prompt: "",
        model: model_id,
        params: { image: image_url }
      )
    end
  end
end
