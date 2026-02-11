# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module MASTER
  # Replicate - Image generation via Replicate API
  module Replicate
    extend self

    API_URL = 'https://api.replicate.com/v1/predictions'

    MODELS = {
      # Image generation
      flux:         'black-forest-labs/flux-1.1-pro',
      flux_pro:     'black-forest-labs/flux-pro',
      flux_dev:     'black-forest-labs/flux-dev',
      sdxl:         'stability-ai/sdxl',
      kandinsky:    'ai-forever/kandinsky-2.2',
      ideogram_v2:  'ideogram-ai/ideogram-v2',
      recraft_v3:   'recraft-ai/recraft-v3',

      # Upscaling/Enhancement
      esrgan:       'nightmareai/real-esrgan',
      gfpgan:       'tencentarc/gfpgan',
      codeformer:   'sczhou/codeformer',
      clarity:      'lucataco/clarity-upscaler',

      # Image captioning
      blip:         'salesforce/blip',

      # Video generation
      svd:          'stability-ai/stable-video-diffusion',
      hailuo:       'minimax/video-01',
      kling:        'kwaivgi/kling-v2.5-turbo-pro',
      luma_ray:     'luma/ray-2',
      wan:          'wan-video/wan-2.5-i2v',
      sora:         'openai/sora-2',

      # Music/Audio generation
      musicgen:     'meta/musicgen',
      bark:         'suno/bark',

      # Transcription
      whisper:      'openai/whisper',

      # 3D generation
      shap_e:       'openai/shap-e'
    }.freeze

    DEFAULT_MODEL = :flux

    # Model categories for filtering
    MODEL_CATEGORIES = {
      image: [:flux, :flux_pro, :flux_dev, :sdxl, :kandinsky, :ideogram_v2, :recraft_v3],
      video: [:svd, :hailuo, :kling, :luma_ray, :wan, :sora],
      upscale: [:esrgan, :gfpgan, :codeformer, :clarity],
      audio: [:musicgen, :bark],
      transcribe: [:whisper],
      caption: [:blip],
      threed: [:shap_e]
    }.freeze

    REPLICATE_TIMEOUT = (ENV['MASTER_REPLICATE_TIMEOUT'] || 300).to_i
    POLL_INTERVAL = (ENV['MASTER_POLL_INTERVAL'] || 2).to_i
    HTTP_OPEN_TIMEOUT = (ENV['MASTER_HTTP_OPEN_TIMEOUT'] || 10).to_i
    HTTP_READ_TIMEOUT = (ENV['MASTER_HTTP_READ_TIMEOUT'] || 60).to_i

    class << self
      def api_key
        ENV['REPLICATE_API_KEY']
      end

      def available?
        !api_key.nil? && !api_key.empty?
      end

      def model_id(name)
        MODELS[name.to_sym] || raise(ArgumentError, "Unknown model: #{name}")
      end

      def models_for(category)
        model_keys = MODEL_CATEGORIES[category.to_sym] || []
        model_keys.map { |key| { name: key, id: MODELS[key] } }
      end

      def generate(prompt:, model: DEFAULT_MODEL, params: {})
        return Result.err("REPLICATE_API_KEY not set") unless available?

        model_id = MODELS[model.to_sym] || MODELS[DEFAULT_MODEL]

        input = { prompt: prompt }.merge(params)

        prediction = create_prediction(model: model_id, input: input)
        return Result.err("Failed to create prediction: #{prediction[:error]}") if prediction[:error]

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
        return Result.err("REPLICATE_API_KEY not set") unless available?

        model_id = MODELS[:esrgan]
        input = { image: image_url, scale: scale }

        prediction = create_prediction(model: model_id, input: input)
        return Result.err("Failed: #{prediction[:error]}") if prediction[:error]

        result = wait_for_completion(prediction[:id])
        return Result.err("Upscale failed: #{result[:error]}") if result[:error]

        Result.ok({ url: result[:output], scale: scale })
      end

      def describe(image_url:)
        return Result.err("REPLICATE_API_KEY not set") unless available?

        model_id = MODELS[:blip]
        input = { image: image_url }

        prediction = create_prediction(model: model_id, input: input)
        return Result.err("Failed: #{prediction[:error]}") if prediction[:error]

        result = wait_for_completion(prediction[:id])
        return Result.err("Describe failed: #{result[:error]}") if result[:error]

        Result.ok({ caption: result[:output] })
      end

      # Video generation helper
      def generate_video(prompt:, model: :svd, params: {})
        return Result.err("REPLICATE_API_KEY not set") unless available?

        model_id = MODELS[model.to_sym] || MODELS[:svd]
        input = { prompt: prompt }.merge(params)

        prediction = create_prediction(model: model_id, input: input)
        return Result.err("Failed to create prediction: #{prediction[:error]}") if prediction[:error]

        result = wait_for_completion(prediction[:id])
        return Result.err("Video generation failed: #{result[:error]}") if result[:error]

        Result.ok({
          id: result[:id],
          url: result[:output],
          model: model_id,
          prompt: prompt
        })
      end

      # Music generation helper
      def generate_music(prompt:, duration: 10, model: :musicgen, params: {})
        return Result.err("REPLICATE_API_KEY not set") unless available?

        model_id = MODELS[model.to_sym] || MODELS[:musicgen]
        input = { prompt: prompt, duration: duration }.merge(params)

        prediction = create_prediction(model: model_id, input: input)
        return Result.err("Failed to create prediction: #{prediction[:error]}") if prediction[:error]

        result = wait_for_completion(prediction[:id])
        return Result.err("Music generation failed: #{result[:error]}") if result[:error]

        Result.ok({
          id: result[:id],
          url: result[:output],
          model: model_id,
          prompt: prompt,
          duration: duration
        })
      end

      # Batch generation with progress
      def batch_generate(prompts, model: DEFAULT_MODEL, params: {})
        return Result.err("REPLICATE_API_KEY not set") unless available?
        return Result.err("Prompts array cannot be empty") if prompts.nil? || prompts.empty?

        results = prompts.map do |prompt|
          generate(prompt: prompt, model: model, params: params)
        end

        Result.ok(results)
      end

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

      def create_prediction(model:, input:)
        uri = URI(API_URL)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = HTTP_OPEN_TIMEOUT
        http.read_timeout = HTTP_READ_TIMEOUT

        request = Net::HTTP::Post.new(uri)
        request['Authorization'] = "Bearer #{api_key}"
        request['Content-Type'] = 'application/json'
        
        body = { input: input }
        body[:version] = model if model
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

      def wait_for_completion(id, timeout: REPLICATE_TIMEOUT)
        uri = URI("#{API_URL}/#{id}")
        start_time = Time.now
        max_polls = (timeout / POLL_INTERVAL).to_i  # Calculate max polls based on timeout

        max_polls.times do
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.open_timeout = HTTP_OPEN_TIMEOUT
          http.read_timeout = HTTP_READ_TIMEOUT

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
            sleep POLL_INTERVAL
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
end
