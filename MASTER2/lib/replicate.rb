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
      # Image generation
      flux:          'black-forest-labs/flux-1.1-pro',
      flux_pro:      'black-forest-labs/flux-1.1-pro',
      flux_kontext:  'black-forest-labs/flux-1.1-pro-kontext',
      flux2:         'black-forest-labs/flux-2.0',
      sdxl:          'stability-ai/sdxl',
      kandinsky:     'ai-forever/kandinsky-2.2',
      # Video generation
      hailuo:        'hailuo-ai/minimax-video-01',
      mochi:         'genmo/mochi-1-preview',
      # Music generation
      musicgen:      'meta/musicgen',
      bark:          'suno-ai/bark',
      stable_audio:  'stability-ai/stable-audio',
      # 3D generation
      triposr:       'stability-ai/triposr',
      trellis:       'microsoft/trellis',
      # Post-processing
      gfpgan:        'tencentarc/gfpgan',
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

      # Generate video from prompt
      def generate_video(prompt:, model: :hailuo, params: {})
        return Result.err("REPLICATE_API_KEY not set") unless available?

        model_id = MODELS[model.to_sym] || MODELS[:hailuo]
        input = { prompt: prompt }.merge(params)

        prediction = create_prediction(model_id, input: input)
        return Result.err("Failed to create video: #{prediction[:error]}") if prediction[:error]

        result = wait_for_completion(prediction[:id], timeout: Timeouts::REPLICATE_TIMEOUT * 2)
        return Result.err("Video generation failed: #{result[:error]}") if result[:error]

        Result.ok({
          id: result[:id],
          url: result[:output],
          model: model_id,
          prompt: prompt
        })
      end

      # Generate music from prompt
      def generate_music(prompt:, model: :musicgen, duration: 30, params: {})
        return Result.err("REPLICATE_API_KEY not set") unless available?

        model_id = MODELS[model.to_sym] || MODELS[:musicgen]
        input = { prompt: prompt, duration: duration }.merge(params)

        prediction = create_prediction(model_id, input: input)
        return Result.err("Failed to create music: #{prediction[:error]}") if prediction[:error]

        result = wait_for_completion(prediction[:id])
        return Result.err("Music generation failed: #{result[:error]}") if result[:error]

        Result.ok({
          id: result[:id],
          url: result[:output],
          model: model_id,
          prompt: prompt
        })
      end

      # Text to speech conversion
      def text_to_speech(text:, model: :bark, voice: 'v2/en_speaker_6', params: {})
        return Result.err("REPLICATE_API_KEY not set") unless available?

        model_id = MODELS[model.to_sym] || MODELS[:bark]
        input = { text: text, voice: voice }.merge(params)

        prediction = create_prediction(model_id, input: input)
        return Result.err("Failed to create speech: #{prediction[:error]}") if prediction[:error]

        result = wait_for_completion(prediction[:id])
        return Result.err("Speech generation failed: #{result[:error]}") if result[:error]

        Result.ok({
          id: result[:id],
          url: result[:output],
          model: model_id,
          text: text
        })
      end

      # Generate 3D model from image or text
      def generate_3d(input:, model: :triposr, params: {})
        return Result.err("REPLICATE_API_KEY not set") unless available?

        model_id = MODELS[model.to_sym] || MODELS[:triposr]
        input_data = input.is_a?(Hash) ? input : { image: input }
        combined_input = input_data.merge(params)

        prediction = create_prediction(model_id, input: combined_input)
        return Result.err("Failed to create 3D model: #{prediction[:error]}") if prediction[:error]

        result = wait_for_completion(prediction[:id])
        return Result.err("3D generation failed: #{result[:error]}") if result[:error]

        Result.ok({
          id: result[:id],
          url: result[:output],
          model: model_id
        })
      end

      # Edit image with Flux models
      def edit_image(image_url:, prompt:, model: :flux_kontext, params: {})
        return Result.err("REPLICATE_API_KEY not set") unless available?

        model_id = MODELS[model.to_sym] || MODELS[:flux_kontext]
        input = { image: image_url, prompt: prompt }.merge(params)

        prediction = create_prediction(model_id, input: input)
        return Result.err("Failed to edit image: #{prediction[:error]}") if prediction[:error]

        result = wait_for_completion(prediction[:id])
        return Result.err("Image editing failed: #{result[:error]}") if result[:error]

        Result.ok({
          id: result[:id],
          url: result[:output],
          model: model_id,
          prompt: prompt
        })
      end

      # Restore/enhance face quality
      def restore_face(image_url:, scale: 2, params: {})
        return Result.err("REPLICATE_API_KEY not set") unless available?

        model_id = MODELS[:gfpgan]
        input = { img: image_url, scale: scale }.merge(params)

        prediction = create_prediction(model_id, input: input)
        return Result.err("Failed to restore face: #{prediction[:error]}") if prediction[:error]

        result = wait_for_completion(prediction[:id])
        return Result.err("Face restoration failed: #{result[:error]}") if result[:error]

        Result.ok({
          id: result[:id],
          url: result[:output],
          scale: scale
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
end
