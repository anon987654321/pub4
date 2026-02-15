# frozen_string_literal: true

module MASTER
  module Cinematic
    # Cinematic presets - film looks and color grades
    def self.presets
      @presets ||= {
        'blade-runner' => {
          description: 'Cyberpunk aesthetic: neon, rain, cyan/orange split tones',
          models: [Replicate::MODELS[:sdxl], Replicate::MODELS[:gfpgan]],
          params: { guidance_scale: 12.0, strength: 0.6 }
        },
        'wes-anderson' => {
          description: 'Symmetrical, pastel palette, centered compositions',
          models: [Replicate::MODELS[:sdxl]],
          params: { guidance_scale: 8.0, strength: 0.5 }
        },
        'noir' => {
          description: 'High contrast black and white, dramatic shadows',
          models: [Replicate::MODELS[:sdxl]],
          params: { guidance_scale: 10.0, strength: 0.7 }
        },
        'golden-hour' => {
          description: 'Warm, soft, glowing light',
          models: [Replicate::MODELS[:sdxl]],
          params: { guidance_scale: 9.0, strength: 0.5 }
        },
        'teal-orange' => {
          description: 'Hollywood blockbuster: teal shadows, orange highlights',
          models: [Replicate::MODELS[:sdxl]],
          params: { guidance_scale: 11.0, strength: 0.6 }
        }
      }.freeze
    end

    # Pipeline builder class
    class Pipeline
      # Generate random creative pipeline
      def self.random(length: 5, category: :all)
        pipeline = new
        models = discover_models(category)

        return Result.err("No models found.") if models.empty?

        length.times do
          model = models.sample
          params = generate_creative_params
          pipeline.chain(model, params)
        end

        Result.ok(pipeline)
      end

      private

      def self.discover_models(category)
        # Use Replicate.models_for to get model IDs from categories
        case category
        when :image
          Replicate.models_for(:image).map { |m| m[:id] }
        when :video
          Replicate.models_for(:video).map { |m| m[:id] }
        when :enhance
          Replicate.models_for(:upscale).map { |m| m[:id] }
        when :audio
          Replicate.models_for(:audio).map { |m| m[:id] }
        when :transcribe
          Replicate.models_for(:transcribe).map { |m| m[:id] }
        when :color
          [Replicate::MODELS[:sdxl]]
        else
          # All models combined
          [:image, :video, :upscale, :audio, :transcribe].flat_map do |cat|
            Replicate.models_for(cat).map { |m| m[:id] }
          end
        end
      end

      def self.generate_creative_params
        {
          'seed' => rand(1..999999),
          'guidance_scale' => rand(5.0..15.0).round(1),
          'num_inference_steps' => rand(20..50)
        }
      end
    end
  end
end
