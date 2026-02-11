# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module MASTER
  # Replicate - Image generation via Replicate API
  module Replicate
    extend self

    API_URL = 'https://api.replicate.com/v1/predictions'

    # Timeout constants (moved from timeouts.rb)
    REPLICATE_TIMEOUT = (ENV['MASTER_REPLICATE_TIMEOUT'] || 300).to_i
    POLL_INTERVAL = (ENV['MASTER_POLL_INTERVAL'] || 2).to_i
    HTTP_OPEN_TIMEOUT = (ENV['MASTER_HTTP_OPEN_TIMEOUT'] || 10).to_i
    HTTP_READ_TIMEOUT = (ENV['MASTER_HTTP_READ_TIMEOUT'] || 60).to_i

    MODELS = {
      flux:      'black-forest-labs/flux-1.1-pro',
      flux2:     'black-forest-labs/flux-2',
      sdxl:      'stability-ai/sdxl',
      kandinsky: 'ai-forever/kandinsky-2.2',
      ideogram:  'ideogram-ai/ideogram-v2',
      recraft:   'recraft-ai/recraft-v3',
    }.freeze

    VIDEO_MODELS = {
      hailuo:    'minimax/hailuo-2.3',
      kling:     'kwaivgi/kling-v2.5-turbo-pro',
      ray:       'luma/ray-2',
      wan:       'wan-video/wan-2.5-i2v',
    }.freeze

    AUDIO_MODELS = {
      musicgen:  'meta/musicgen',
      bark:      'suno/bark',
    }.freeze

    ENHANCE_MODELS = {
      esrgan:    'nightmareai/real-esrgan',
      gfpgan:    'tencentarc/gfpgan',
      codeformer: 'sczhou/codeformer',
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
        prediction = create_prediction(model: model_id, input: input)
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
        return Result.err("REPLICATE_API_KEY not set") unless available?

        model_id = 'nightmareai/real-esrgan'
        input = { image: image_url, scale: scale }

        prediction = create_prediction(model: model_id, input: input)
        return Result.err("Failed: #{prediction[:error]}") if prediction[:error]

        result = wait_for_completion(prediction[:id])
        return Result.err("Upscale failed: #{result[:error]}") if result[:error]

        Result.ok({ url: result[:output], scale: scale })
      end

      def describe(image_url:)
        return Result.err("REPLICATE_API_KEY not set") unless available?

        model_id = 'salesforce/blip'
        input = { image: image_url }

        prediction = create_prediction(model: model_id, input: input)
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

      # Generate video using AI models
      def generate_video(prompt:, model: :hailuo, params: {})
        return Result.err("REPLICATE_API_KEY not set") unless available?

        model_id = VIDEO_MODELS[model.to_sym] || VIDEO_MODELS[:hailuo]
        input = { prompt: prompt }.merge(params)

        prediction = create_prediction(model: model_id, input: input)
        return Result.err("Failed to create prediction: #{prediction[:error]}") if prediction[:error]

        result = wait_for_completion(prediction[:id], timeout: 300)
        return Result.err("Video generation failed: #{result[:error]}") if result[:error]

        Result.ok({
          id: result[:id],
          urls: result[:output],
          model: model_id,
          prompt: prompt
        })
      end

      # Generate music using AI models
      def generate_music(prompt:, model: :musicgen, duration: 10, params: {})
        return Result.err("REPLICATE_API_KEY not set") unless available?

        model_id = AUDIO_MODELS[model.to_sym] || AUDIO_MODELS[:musicgen]
        input = { prompt: prompt, duration: duration }.merge(params)

        prediction = create_prediction(model: model_id, input: input)
        return Result.err("Failed to create prediction: #{prediction[:error]}") if prediction[:error]

        result = wait_for_completion(prediction[:id], timeout: 120)
        return Result.err("Music generation failed: #{result[:error]}") if result[:error]

        Result.ok({
          id: result[:id],
          urls: result[:output],
          model: model_id,
          prompt: prompt,
          duration: duration
        })
      end

      # Text to speech conversion
      def text_to_speech(text:, model: :bark, voice: nil, params: {})
        return Result.err("REPLICATE_API_KEY not set") unless available?

        model_id = AUDIO_MODELS[model.to_sym] || AUDIO_MODELS[:bark]
        input = { text: text }.merge(params)
        input[:voice] = voice if voice

        prediction = create_prediction(model: model_id, input: input)
        return Result.err("Failed to create prediction: #{prediction[:error]}") if prediction[:error]

        result = wait_for_completion(prediction[:id], timeout: 60)
        return Result.err("Text-to-speech failed: #{result[:error]}") if result[:error]

        Result.ok({
          id: result[:id],
          url: result[:output],
          model: model_id,
          text: text
        })
      end

      # Generate 3D model from image
      def generate_3d(image_url:, model: :triposr, params: {})
        return Result.err("REPLICATE_API_KEY not set") unless available?

        model_id = 'stabilityai/triposr'
        input = { image: image_url }.merge(params)

        prediction = create_prediction(model: model_id, input: input)
        return Result.err("Failed to create prediction: #{prediction[:error]}") if prediction[:error]

        result = wait_for_completion(prediction[:id], timeout: 180)
        return Result.err("3D generation failed: #{result[:error]}") if result[:error]

        Result.ok({
          id: result[:id],
          url: result[:output],
          model: model_id
        })
      end

      # Edit image with AI
      def edit_image(image_url:, prompt:, model: :flux_kontext, params: {})
        return Result.err("REPLICATE_API_KEY not set") unless available?

        model_id = 'black-forest-labs/flux-kontext'
        input = { image: image_url, prompt: prompt }.merge(params)

        prediction = create_prediction(model: model_id, input: input)
        return Result.err("Failed to create prediction: #{prediction[:error]}") if prediction[:error]

        result = wait_for_completion(prediction[:id])
        return Result.err("Image editing failed: #{result[:error]}") if result[:error]

        Result.ok({
          id: result[:id],
          urls: result[:output],
          model: model_id,
          prompt: prompt
        })
      end

      # Restore/enhance faces in images
      def restore_face(image_url:, params: {})
        return Result.err("REPLICATE_API_KEY not set") unless available?

        model_id = ENHANCE_MODELS[:gfpgan]
        input = { image: image_url }.merge(params)

        prediction = create_prediction(model: model_id, input: input)
        return Result.err("Failed to create prediction: #{prediction[:error]}") if prediction[:error]

        result = wait_for_completion(prediction[:id])
        return Result.err("Face restoration failed: #{result[:error]}") if result[:error]

        Result.ok({
          id: result[:id],
          url: result[:output],
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
      rescue StandardError => e
        $stderr.puts "Replicate: download_file failed for #{url}: #{e.message}"
        false
      end

      private

      def create_prediction(model:, input:, version: nil)
        # All parameters are now keyword arguments for clarity
        actual_input = input
        actual_version = version || model
        
        uri = URI(API_URL)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = HTTP_OPEN_TIMEOUT
        http.read_timeout = HTTP_READ_TIMEOUT

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
      rescue StandardError => e
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
      rescue StandardError => e
        $stderr.puts "Replicate: wait_for_completion error: #{e.class} - #{e.message}"
        { error: e.message }
      end
    end
  end
end
