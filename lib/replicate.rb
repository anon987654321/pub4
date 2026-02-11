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
        http.open_timeout = 10
        http.read_timeout = 60

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
        { error: e.message }
      end

      def wait_for_completion(id, timeout: 300)
        uri = URI("#{API_URL}/#{id}")
        start_time = Time.now
        max_polls = 150  # Safety limit: 150 polls * 2s = 300s max

        max_polls.times do
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.open_timeout = 10
          http.read_timeout = 30

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
            sleep 2
          else
            return { error: "Unknown status: #{data[:status]}" }
          end

          return { error: 'Timeout waiting for generation' } if Time.now - start_time > timeout
        end

        { error: 'Max polls exceeded' }
      rescue Net::OpenTimeout, Net::ReadTimeout
        { error: 'Poll request timed out' }
      rescue => e
        { error: e.message }
      end
    end
  end
end
