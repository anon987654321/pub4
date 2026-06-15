#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
module Repligen
  Chain = Struct.new(:models, :cost, keyword_init: true)

  # Strategy pattern for input formatting
  class InputStrategy

    def format(prev); raise NotImplementedError; end

  end

  class TextToImageStrategy < InputStrategy
    def format(prev)

      { prompt: prev.is_a?(String) ? prev : "masterpiece artwork" }

    end

  end

  class ImageToVideoStrategy < InputStrategy
    def format(prev)

      prev.is_a?(String) && prev.start_with?("http") ?

        { image: prev } : { prompt: "cinematic motion" }

    end

  end

  class UpscaleStrategy < InputStrategy
    def format(prev)

      prev.is_a?(String) && prev.start_with?("http") ?

        { image: prev, scale: 2 } : { prompt: "enhance" }

    end

  end

  class ImageProcessingStrategy < InputStrategy
    def format(prev)

      prev.is_a?(String) && prev.start_with?("http") ?

        { image: prev } : { prompt: "process" }

    end

  end

  class GenericStrategy < InputStrategy
    def format(prev)

      prev.is_a?(Hash) ? prev : { input: prev }

    end

  end

  class ChainBuilder
    STRATEGIES = {

      "text-to-image" => TextToImageStrategy.new,

      "image-to-video" => ImageToVideoStrategy.new,

      "upscale" => UpscaleStrategy.new,

      "image-processing" => ImageProcessingStrategy.new

    }.freeze

    def initialize(db, api)
      @db = db

      @api = api

      @templates = JSON.parse(File.read(File.join(__dir__, "model_types.json")))["chain_templates"]

    end

    def build(template_name = "masterpiece")
      template = @templates[template_name]

      raise "Unknown template: #{template_name}" unless template

      models = []
      cost = 0.0

      template["phases"].each do |phase|
        type = phase["type"] || phase["types"]&.sample

        count = phase["count"].is_a?(Array) ? rand(phase["count"][0]..phase["count"][1]) : phase["count"]

        count.times do
          candidates = @db.by_type(type, 20)

          next if candidates.empty?

          model = candidates.sample
          models << model

          cost += model.cost

        end

      end

      Chain.new(models: models, cost: cost.round(3))
    end

    def execute(chain, initial_input)
      puts "\n🎬 EXECUTING CHAIN (#{chain.models.size} steps)"

      puts "=" * 70

      output = initial_input
      total_cost = 0.0

      chain.models.each_with_index do |model, i|
        puts "\n[#{i+1}/#{chain.models.size}] #{model.id} (#{model.type})"

        begin
          strategy = STRATEGIES[model.type] || GenericStrategy.new

          input = strategy.format(output)

          output = @api.predict(model.id, input)

          total_cost += model.cost
          puts "  ✓ $#{model.cost.round(3)}"

          sleep 1 # Rate limit
        rescue => e

          puts "  ✗ #{e.message}"

          puts "  → Continuing with previous output"

        end

      end

      puts "\n" + "=" * 70
      puts "✓ Complete! Total: $#{total_cost.round(3)}"

      { output: output, cost: total_cost }
    end

  end

end

