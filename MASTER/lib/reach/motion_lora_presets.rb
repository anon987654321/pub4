# frozen_string_literal: true

module Master
  module Reach
    # Loads camera Motion LoRA presets for ComfyUI AnimateDiff inference + training reference.
    module MotionLoraPresets
      PATH = Master.data_path("comfyui", "motion_lora_presets.yml").freeze

      module_function

      def load
        return @cache if defined?(@cache) && @cache

        @cache = File.file?(PATH) ? (Master.load_yaml(PATH) || {}) : {}
      end

      def names
        load.fetch("presets", {}).keys.sort
      end

      def resolve(name)
        key = name.to_s.strip
        return nil if key.empty?

        preset = load.dig("presets", key)
        return nil unless preset

        {
          motion_lora: preset["lora_file"],
          motion_lora_weight: preset.fetch("inference_strength", 0.75).to_f,
          camera_phrase: preset["camera_phrase"].to_s,
          stack_lora: preset["stack_lora"],
          stack_strength: preset["stack_strength"]&.to_f,
          caption_template: preset["caption_template"],
        }
      end

      def training_defaults
        load.fetch("training_defaults", {})
      end

      def caption_for(preset_name, subject:)
        preset = load.dig("presets", preset_name.to_s) || {}
        template = preset["caption_template"].to_s
        return subject if template.empty?

        template.gsub("{subject}", subject.to_s)
      end

      def apply!(opts, preset_name:)
        resolved = resolve(preset_name)
        return opts unless resolved

        opts[:motion_lora] ||= resolved[:motion_lora]
        opts[:motion_lora_weight] ||= resolved[:motion_lora_weight]
        opts[:motion_lora_2] ||= resolved[:stack_lora]
        opts[:motion_lora_2_weight] ||= resolved[:stack_strength]
        opts[:camera_phrase] = resolved[:camera_phrase] if resolved[:camera_phrase] && !resolved[:camera_phrase].empty?
        opts
      end
    end
  end
end