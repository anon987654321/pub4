# frozen_string_literal: true

module MASTER
  module Replicate
    # Generators - high-level generation methods for different media types
    module Generators
      module_function

      # Generate image from text prompt
      def generate(prompt:, model: Models::DEFAULT_MODEL, params: {})
        return Result.err(TOKEN_NOT_SET) unless Replicate.available?

        model_id = Models::MODELS[model.to_sym] || Models::MODELS[Models::DEFAULT_MODEL]

        input = { prompt: prompt }.merge(params)

        # Create prediction
        prediction = Client.create_prediction(model: model_id, input: input)
        return Result.err("Failed to create prediction: #{prediction[:error]}") if prediction[:error]

        # Poll for completion
        result = Client.wait_for_completion(prediction[:id])
        return Result.err("Generation failed: #{result[:error]}") if result[:error]

        Result.ok({
          id: result[:id],
          urls: result[:output],
          model: model_id,
          prompt: prompt
        })
      end

      # Upscale an image
      def upscale(image_url:, scale: 4)
        return Result.err(TOKEN_NOT_SET) unless Replicate.available?

        model_id = Models::MODELS[:esrgan]
        input = { image: image_url, scale: scale }

        prediction = Client.create_prediction(model: model_id, input: input)
        return Result.err("Failed: #{prediction[:error]}") if prediction[:error]

        result = Client.wait_for_completion(prediction[:id])
        return Result.err("Upscale failed: #{result[:error]}") if result[:error]

        Result.ok({ url: result[:output], scale: scale })
      end

      # Describe/caption an image
      def describe(image_url:)
        return Result.err(TOKEN_NOT_SET) unless Replicate.available?

        model_id = Models::MODELS[:blip]
        input = { image: image_url }

        prediction = Client.create_prediction(model: model_id, input: input)
        return Result.err("Failed: #{prediction[:error]}") if prediction[:error]

        result = Client.wait_for_completion(prediction[:id])
        return Result.err("Describe failed: #{result[:error]}") if result[:error]

        Result.ok({ caption: result[:output] })
      end

      # Generate video from prompt
      def generate_video(prompt:, model: :svd, params: {})
        return Result.err(TOKEN_NOT_SET) unless Replicate.available?

        model_sym = model.to_sym
        return Result.err("Unknown model: #{model}") unless Models::MODELS.key?(model_sym)

        model_id = Models::MODELS[model_sym]
        input = { prompt: prompt }.merge(params)

        prediction = Client.create_prediction(model: model_id, input: input)
        return Result.err("Failed to create prediction: #{prediction[:error]}") if prediction[:error]

        result = Client.wait_for_completion(prediction[:id])
        return Result.err("Video generation failed: #{result[:error]}") if result[:error]

        Result.ok({
          id: result[:id],
          urls: result[:output],
          model: model_id,
          prompt: prompt
        })
      end

      # Generate music from prompt
      def generate_music(prompt:, duration: 10, model: :musicgen, params: {})
        return Result.err(TOKEN_NOT_SET) unless Replicate.available?

        model_sym = model.to_sym
        return Result.err("Unknown model: #{model}") unless Models::MODELS.key?(model_sym)

        model_id = Models::MODELS[model_sym]
        input = { prompt: prompt, duration: duration }.merge(params)

        prediction = Client.create_prediction(model: model_id, input: input)
        return Result.err("Failed to create prediction: #{prediction[:error]}") if prediction[:error]

        result = Client.wait_for_completion(prediction[:id])
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
      def batch_generate(prompts, model: Models::DEFAULT_MODEL, params: {})
        unless Replicate.available?
          return prompts.map { Result.err(TOKEN_NOT_SET) }
        end

        prompts.map do |prompt|
          generate(prompt: prompt, model: model, params: params)
        end
      end

      # Generic model runner - supports any Replicate model
      def run(model_id:, input:, params: {})
        return Result.err(TOKEN_NOT_SET) unless Replicate.available?

        combined_input = input.merge(params)

        prediction = Client.create_prediction(model: model_id, input: combined_input)
        return Result.err("Failed to create prediction: #{prediction[:error]}") if prediction[:error]

        result = Client.wait_for_completion(prediction[:id])
        return Result.err("Model run failed: #{result[:error]}") if result[:error]

        Result.ok({
          id: result[:id],
          output: result[:output],
          model: model_id
        })
      end
    end
  end
end
