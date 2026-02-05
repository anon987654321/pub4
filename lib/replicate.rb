# frozen_string_literal: true

require 'net/http'
require 'json'
require 'base64'
require 'fileutils'

module MASTER
  module Replicate
    API_URL = 'https://api.replicate.com/v1/predictions'
    OUTPUT_DIR = File.join(MASTER::ROOT, 'var', 'replicate')

    MODELS = {
      flux: 'black-forest-labs/flux-schnell',
      sdxl: 'stability-ai/sdxl',
      llava: 'yorickvp/llava-13b',
      whisper: 'openai/whisper',
      musicgen: 'meta/musicgen'
    }.freeze

    class << self
      def generate_image(prompt, model: :flux)
        run_model(MODELS[model], { prompt: prompt })
      end

      def describe_image(path)
        return 'File not found' unless File.exist?(path)

        data = Base64.strict_encode64(File.binread(path))
        ext = File.extname(path).sub('.', '')
        uri = "data:image/#{ext};base64,#{data}"

        run_model(MODELS[:llava], { image: uri, prompt: 'Describe this image.' })
      end

      def transcribe(path)
        return 'File not found' unless File.exist?(path)

        data = Base64.strict_encode64(File.binread(path))
        run_model(MODELS[:whisper], { audio: "data:audio/mp3;base64,#{data}" })
      end

      private

      def run_model(model, input)
        api_key = ENV['REPLICATE_API_TOKEN']
        return 'REPLICATE_API_TOKEN not set' unless api_key

        uri = URI(API_URL)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)
        request['Authorization'] = "Token #{api_key}"
        request['Content-Type'] = 'application/json'
        request.body = { version: model, input: input }.to_json

        response = http.request(request)
        data = JSON.parse(response.body)

        return data['error'] if data['error']

        poll_prediction(data['id'], api_key)
      end

      def poll_prediction(id, api_key, timeout: 300)
        uri = URI("#{API_URL}/#{id}")
        start = Time.now

        loop do
          return 'Timeout' if Time.now - start > timeout

          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true

          request = Net::HTTP::Get.new(uri)
          request['Authorization'] = "Token #{api_key}"

          response = http.request(request)
          data = JSON.parse(response.body)

          case data['status']
          when 'succeeded'
            output = data['output']
            return save_output(output)
          when 'failed'
            return data['error'] || 'Failed'
          end

          sleep 2
        end
      end

      def save_output(output)
        FileUtils.mkdir_p(OUTPUT_DIR)

        case output
        when String
          if output.start_with?('http')
            filename = "#{Time.now.to_i}_#{File.basename(URI.parse(output).path)}"
            path = File.join(OUTPUT_DIR, filename)
            download(output, path)
            path
          else
            output
          end
        when Array
          output.map { |o| save_output(o) }.join("\n")
        else
          output.to_s
        end
      end

      def download(url, path)
        uri = URI(url)
        Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
          response = http.get(uri.request_uri)
          File.binwrite(path, response.body)
        end
      end
    end
  end
end
