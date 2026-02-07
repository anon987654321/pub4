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
        ENV['REPLICATE_API_TOKEN']
      end

      def available?
        !api_key.nil? && !api_key.empty?
      end

      def generate(prompt:, model: DEFAULT_MODEL, params: {})
        return Result.err("REPLICATE_API_TOKEN not set") unless available?

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

      private

      def create_prediction(model_version, input)
        uri = URI(API_URL)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)
        request['Authorization'] = "Bearer #{api_key}"
        request['Content-Type'] = 'application/json'
        request.body = { version: model_version, input: input }.to_json

        response = http.request(request)
        data = JSON.parse(response.body, symbolize_names: true)

        if data[:id]
          { id: data[:id] }
        else
          { error: data[:detail] || 'Unknown error' }
        end
      rescue => e
        { error: e.message }
      end

      def wait_for_completion(id, timeout: 300)
        uri = URI("#{API_URL}/#{id}")
        start_time = Time.now

        loop do
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true

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
      rescue => e
        { error: e.message }
      end
    end
  end
end
