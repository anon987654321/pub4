# frozen_string_literal: true

require "json"
require "uri"
require_relative "result"
require_relative "replicate/media"
require_relative "replicate/narration"

module MASTER
  # Replicate - Image generation via Replicate API
  module Replicate
    TOKEN_NOT_SET = "REPLICATE_API_TOKEN not set."

    API_URL = "https://api.replicate.com/v1/predictions"

    # MODELS and MODEL_CATEGORIES are derived from data/replicate_models.yml.
    # The YAML is the single source of truth; these constants are convenience aliases.
    MODELS_FILE = File.expand_path("../data/replicate_models.yml", __dir__).freeze

    def self.configured_models
      @configured_models ||= begin
        YAML.safe_load_file(MODELS_FILE, symbolize_names: true)
      rescue StandardError => e
        Logging.warn("replicate: failed to load #{MODELS_FILE}: #{e.message}", subsystem: "replicate") if defined?(Logging)
        []
      end
    end

    # { flux: 'black-forest-labs/flux-1.1-pro', ... }
    def self.models_hash
      @models_hash ||= configured_models.each_with_object({}) do |m, h|
        h[m[:alias].to_sym] = m[:id]
      end.freeze
    end

    # { image: [:flux, :flux_pro, ...], video: [...], ... }
    def self.categories_hash
      @categories_hash ||= configured_models.each_with_object({}) do |m, h|
        key = m[:category].to_sym
        (h[key] ||= []) << m[:alias].to_sym
      end.transform_values(&:freeze).freeze
    end

    # Backward-compatible constant aliases (populated lazily after YAML load)
    MODELS = Hash.new { |_, k| models_hash[k] }.tap do |h|
      h.merge!(models_hash)
    rescue StandardError
      {}
    end.freeze
    MODEL_CATEGORIES = Hash.new { |_, k| categories_hash[k] }.tap do |h|
      h.merge!(categories_hash)
    rescue StandardError
      {}
    end.freeze

    DEFAULT_MODEL = :flux

    # Timeout constants (from timeouts.rb)
    REPLICATE_TIMEOUT = (ENV["MASTER_REPLICATE_TIMEOUT"] || 300).to_i
    POLL_INTERVAL = (ENV["MASTER_POLL_INTERVAL"] || 2).to_i
    HTTP_OPEN_TIMEOUT = (ENV["MASTER_HTTP_OPEN_TIMEOUT"] || 10).to_i
    HTTP_READ_TIMEOUT = (ENV["MASTER_HTTP_READ_TIMEOUT"] || 60).to_i

    class << self
      def circuit_key
        "replicate_api"
      end

      def api_key
        ENV["REPLICATE_API_TOKEN"] || ENV.fetch("REPLICATE_API_KEY", nil)
      end

      def available?
        !api_key.nil? && !api_key.empty?
      end

      def generate(prompt:, model: DEFAULT_MODEL, params: {})
        return Result.err(TOKEN_NOT_SET) unless available?

        if defined?(CircuitBreaker) && !CircuitBreaker.circuit_closed?(circuit_key)
          return Result.err("Replicate circuit open -- API temporarily unavailable")
        end

        model_id = if MODELS.key?(model.to_sym)
                     MODELS[model.to_sym]
                   elsif MODELS.values.include?(model.to_s)
                     model.to_s
                   else
                     MODELS[DEFAULT_MODEL]
                   end

        input = { prompt: prompt }.merge(params)

        prediction = create_prediction(model: model_id, input: input)
        return Result.err("Failed to create prediction: #{prediction[:error]}") if prediction[:error]

        result = wait_for_completion(prediction[:id])
        return Result.err("Generation failed: #{result[:error]}") if result[:error]

        if defined?(MASTER::Logging)
          Logging.info("Replicate prediction completed", model: model_id, prediction_id: result[:id])
        end

        Result.ok({
                    id: result[:id],
                    urls: result[:output],
                    model: model_id,
                    prompt: prompt,
                  })
      rescue StandardError => err
        CircuitBreaker.open_circuit!(circuit_key) if defined?(CircuitBreaker)
        Result.err("Replicate error: #{err.message}")
      end

      def upscale(image_url:, scale: 4)
        return Result.err(TOKEN_NOT_SET) unless available?

        if defined?(CircuitBreaker) && !CircuitBreaker.circuit_closed?(circuit_key)
          return Result.err("Replicate circuit open -- API temporarily unavailable")
        end

        model_id = MODELS[:esrgan]
        input = { image: image_url, scale: scale }

        prediction = create_prediction(model: model_id, input: input)
        return Result.err("Failed: #{prediction[:error]}") if prediction[:error]

        result = wait_for_completion(prediction[:id])
        return Result.err("Upscale failed: #{result[:error]}") if result[:error]

        if defined?(MASTER::Logging)
          Logging.info("Replicate prediction completed", model: model_id, prediction_id: result[:id])
        end

        Result.ok({ url: result[:output], scale: scale })
      rescue StandardError => err
        CircuitBreaker.open_circuit!(circuit_key) if defined?(CircuitBreaker)
        Result.err("Replicate error: #{err.message}")
      end

      def describe(image_url:)
        return Result.err(TOKEN_NOT_SET) unless available?

        if defined?(CircuitBreaker) && !CircuitBreaker.circuit_closed?(circuit_key)
          return Result.err("Replicate circuit open -- API temporarily unavailable")
        end

        model_id = MODELS[:blip]
        input = { image: image_url }

        prediction = create_prediction(model: model_id, input: input)
        return Result.err("Failed: #{prediction[:error]}") if prediction[:error]

        result = wait_for_completion(prediction[:id])
        return Result.err("Describe failed: #{result[:error]}") if result[:error]

        if defined?(MASTER::Logging)
          Logging.info("Replicate prediction completed", model: model_id, prediction_id: result[:id])
        end

        Result.ok({ caption: result[:output] })
      rescue StandardError => err
        CircuitBreaker.open_circuit!(circuit_key) if defined?(CircuitBreaker)
        Result.err("Replicate error: #{err.message}")
      end

      # Edit an existing image with a text prompt (FLUX Kontext -- no mask needed).
      # image_url: publicly accessible image URL
      # prompt:    natural language edit instruction, e.g. "change the sky to sunset"
      def edit(image_url:, prompt:, model: :flux_kontext_pro, params: {})
        return Result.err(TOKEN_NOT_SET) unless available?
        return Result.err("Replicate circuit open") if defined?(CircuitBreaker) && !CircuitBreaker.circuit_closed?(circuit_key)

        model_id = MODELS.fetch(model.to_sym, MODELS[:flux_kontext_pro])
        input = { prompt: prompt, input_image: image_url }.merge(params)

        prediction = create_prediction(model: model_id, input: input)
        return Result.err("Failed: #{prediction[:error]}") if prediction[:error]

        result = wait_for_completion(prediction[:id])
        return Result.err("Edit failed: #{result[:error]}") if result[:error]

        Logging.info("Replicate prediction completed", model: model_id, prediction_id: result[:id]) if defined?(MASTER::Logging)
        Result.ok({ id: result[:id], urls: result[:output], model: model_id, prompt: prompt })
      rescue StandardError => err
        CircuitBreaker.open_circuit!(circuit_key) if defined?(CircuitBreaker)
        Result.err("Replicate error: #{err.message}")
      end

      # Inpaint or outpaint an image (FLUX Fill -- requires mask).
      # image_url: source image; mask_url: white=edit area, black=keep; prompt: what to fill
      def inpaint(image_url:, prompt:, mask_url: nil, model: :flux_fill_pro, params: {})
        return Result.err(TOKEN_NOT_SET) unless available?
        return Result.err("Replicate circuit open") if defined?(CircuitBreaker) && !CircuitBreaker.circuit_closed?(circuit_key)

        model_id = MODELS.fetch(model.to_sym, MODELS[:flux_fill_pro])
        input = { prompt: prompt, image: image_url }.merge(params)
        input[:mask] = mask_url if mask_url

        prediction = create_prediction(model: model_id, input: input)
        return Result.err("Failed: #{prediction[:error]}") if prediction[:error]

        result = wait_for_completion(prediction[:id])
        return Result.err("Inpaint failed: #{result[:error]}") if result[:error]

        Logging.info("Replicate prediction completed", model: model_id, prediction_id: result[:id]) if defined?(MASTER::Logging)
        Result.ok({ id: result[:id], urls: result[:output], model: model_id, prompt: prompt })
      rescue StandardError => err
        CircuitBreaker.open_circuit!(circuit_key) if defined?(CircuitBreaker)
        Result.err("Replicate error: #{err.message}")
      end

      # Create variations of an image (FLUX Redux -- no prompt, preserves key elements).
      def vary(image_url:, model: :flux_redux, params: {})
        return Result.err(TOKEN_NOT_SET) unless available?
        return Result.err("Replicate circuit open") if defined?(CircuitBreaker) && !CircuitBreaker.circuit_closed?(circuit_key)

        model_id = MODELS.fetch(model.to_sym, MODELS[:flux_redux])
        input = { redux_image: image_url }.merge(params)

        prediction = create_prediction(model: model_id, input: input)
        return Result.err("Failed: #{prediction[:error]}") if prediction[:error]

        result = wait_for_completion(prediction[:id])
        return Result.err("Variation failed: #{result[:error]}") if result[:error]

        Logging.info("Replicate prediction completed", model: model_id, prediction_id: result[:id]) if defined?(MASTER::Logging)
        Result.ok({ id: result[:id], urls: result[:output], model: model_id })
      rescue StandardError => err
        CircuitBreaker.open_circuit!(circuit_key) if defined?(CircuitBreaker)
        Result.err("Replicate error: #{err.message}")
      end

      # Segment objects in an image using SAM 2.
      # Returns masks/segmentation data for the image.
      def segment(image_url:, model: :sam2, params: {})
        return Result.err(TOKEN_NOT_SET) unless available?
        return Result.err("Replicate circuit open") if defined?(CircuitBreaker) && !CircuitBreaker.circuit_closed?(circuit_key)

        model_id = MODELS.fetch(model.to_sym, MODELS[:sam2])
        input = { image: image_url }.merge(params)

        prediction = create_prediction(model: model_id, input: input)
        return Result.err("Failed: #{prediction[:error]}") if prediction[:error]

        result = wait_for_completion(prediction[:id])
        return Result.err("Segmentation failed: #{result[:error]}") if result[:error]

        Logging.info("Replicate prediction completed", model: model_id, prediction_id: result[:id]) if defined?(MASTER::Logging)
        Result.ok({ id: result[:id], output: result[:output], model: model_id })
      rescue StandardError => err
        CircuitBreaker.open_circuit!(circuit_key) if defined?(CircuitBreaker)
        Result.err("Replicate error: #{err.message}")
      end

      # Edge-guided image generation from a sketch/edge map (FLUX Canny).
      # control_image: canny edge map or sketch; prompt: what to generate
      def sketch(control_image:, prompt:, model: :flux_canny, params: {})
        return Result.err(TOKEN_NOT_SET) unless available?
        return Result.err("Replicate circuit open") if defined?(CircuitBreaker) && !CircuitBreaker.circuit_closed?(circuit_key)

        model_id = MODELS.fetch(model.to_sym, MODELS[:flux_canny])
        input = { control_image: control_image, prompt: prompt }.merge(params)

        prediction = create_prediction(model: model_id, input: input)
        return Result.err("Failed: #{prediction[:error]}") if prediction[:error]

        result = wait_for_completion(prediction[:id])
        return Result.err("Sketch-to-image failed: #{result[:error]}") if result[:error]

        Logging.info("Replicate prediction completed", model: model_id, prediction_id: result[:id]) if defined?(MASTER::Logging)
        Result.ok({ id: result[:id], urls: result[:output], model: model_id, prompt: prompt })
      rescue StandardError => err
        CircuitBreaker.open_circuit!(circuit_key) if defined?(CircuitBreaker)
        Result.err("Replicate error: #{err.message}")
      end


      def run(model_id:, input:, params: {})
        return Result.err(TOKEN_NOT_SET) unless available?

        if defined?(CircuitBreaker) && !CircuitBreaker.circuit_closed?(circuit_key)
          return Result.err("Replicate circuit open -- API temporarily unavailable")
        end

        combined_input = input.merge(params)

        prediction = create_prediction(model: model_id, input: combined_input)
        return Result.err("Failed to create prediction: #{prediction[:error]}") if prediction[:error]

        result = wait_for_completion(prediction[:id])
        return Result.err("Model run failed: #{result[:error]}") if result[:error]

        if defined?(MASTER::Logging)
          Logging.info("Replicate prediction completed", model: model_id, prediction_id: result[:id])
        end

        Result.ok({
                    id: result[:id],
                    output: result[:output],
                    model: model_id,
                  })
      rescue StandardError => err
        CircuitBreaker.open_circuit!(circuit_key) if defined?(CircuitBreaker)
        Result.err("Replicate error: #{err.message}")
      end

      # Lookup model ID by symbol name
      def model_id(name)
        model = MODELS[name.to_sym]
        raise ArgumentError, "Unknown model: #{name}" unless model

        model
      end

      # Get all models for a category
      def models_for(category)
        model_names = MODEL_CATEGORIES[category.to_sym]
        return [] unless model_names

        model_names.map do |name|
          { name: name, id: MODELS[name] }
        end
      end

      private

      # Delegate all HTTP to Client (async-http, Falcon ecosystem)
      def create_prediction(model:, input:)
        Client.create_prediction(model: model, input: input)
      end

      def wait_for_completion(id, timeout: REPLICATE_TIMEOUT)
        Client.wait_for_completion(id, timeout: timeout)
      end
    end
  end
end
