# frozen_string_literal: true

module MASTER
  module Replicate
    class << self
      # Generate video from prompt
      # @param prompt [String] Text prompt for video generation
      # @param model [Symbol] Video model to use (default: :svd)
      # @param params [Hash] Additional parameters to pass to the model
      # @return [Result] Result object with video URL or error
      def generate_video(prompt:, model: :svd, params: {})
        return Result.err(TOKEN_NOT_SET) unless available?

        model_sym = model.to_sym
        return Result.err("Unknown model: #{model}") unless MODELS.key?(model_sym)

        model_id = MODELS[model_sym]
        input = { prompt: prompt }.merge(params)

        prediction = create_prediction(model: model_id, input: input)
        return Result.err("Failed to create prediction: #{prediction[:error]}") if prediction[:error]

        result = wait_for_completion(prediction[:id])
        return Result.err("Video generation failed: #{result[:error]}") if result[:error]

        Result.ok({
          id: result[:id],
          urls: result[:output],
          model: model_id,
          prompt: prompt
        })
      end

      # Generate music from prompt
      # @param prompt [String] Text description of music to generate
      # @param duration [Integer] Length in seconds (default: 10)
      # @param model [Symbol] Audio model to use (default: :musicgen)
      # @param params [Hash] Additional parameters to pass to the model
      # @return [Result] Result object with audio URL or error
      def generate_music(prompt:, duration: 10, model: :musicgen, params: {})
        return Result.err(TOKEN_NOT_SET) unless available?

        model_sym = model.to_sym
        return Result.err("Unknown model: #{model}") unless MODELS.key?(model_sym)

        model_id = MODELS[model_sym]
        input = { prompt: prompt, duration: duration }.merge(params)

        prediction = create_prediction(model: model_id, input: input)
        return Result.err("Failed to create prediction: #{prediction[:error]}") if prediction[:error]

        result = wait_for_completion(prediction[:id])
        return Result.err("Music generation failed: #{result[:error]}") if result[:error]

        Result.ok({
          id: result[:id],
          urls: result[:output],
          model: model_id,
          prompt: prompt,
          duration: duration
        })
      end

      # Batch generate multiple prompts
      # @param prompts [Array<String>] Array of text prompts
      # @param model [Symbol] Model to use (default: DEFAULT_MODEL)
      # @param params [Hash] Additional parameters to pass to all generations
      # @return [Array<Result>] Array of Result objects
      def batch_generate(prompts, model: DEFAULT_MODEL, params: {})
        unless available?
          return prompts.map { |_| Result.err(TOKEN_NOT_SET) }
        end

        prompts.map do |prompt|
          generate(prompt: prompt, model: model, params: params)
        end
      end

      # Download file from URL to local path
      def download_file(url, path, max_redirects: 3)
        uri = URI(url)
        max_redirects.times do
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = (uri.scheme == 'https')

          response = http.get(uri.request_uri)
          case response
          when Net::HTTPSuccess
            FileUtils.mkdir_p(File.dirname(path))
            File.binwrite(path, response.body)
            return true
          when Net::HTTPRedirection
            uri = URI(response['location'])
          else
            return false
          end
        end
        false
      rescue StandardError => e
        Logging.warn("Replicate: download failed for #{url}: #{e.message}") if defined?(MASTER::Logging)
        false
      end
    end
  end
end
