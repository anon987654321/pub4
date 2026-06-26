# frozen_string_literal: true

module Master
  module Reach
    # Camera Motion LoRA presets — training captions, inference weights, stack combos.
    module MotionLoraPresets
      PATH = Master.data_path("comfyui", "motion_lora_presets.yml").freeze

      module_function

      def load
        return @cache if defined?(@cache) && @cache

        @cache = File.file?(PATH) ? (Master.load_yaml(PATH) || {}) : {}
      end

      def names = load.fetch("presets", {}).keys.sort
      def stack_names = load.fetch("stack_combos", {}).keys.sort

      def resolve(name)
        preset = load.dig("presets", name.to_s.strip)
        return nil unless preset

        preset_entry(preset)
      end

      def resolve_stack(combo_or_list)
        if combo_or_list.is_a?(String) && load.dig("stack_combos", combo_or_list)
          combo = load.dig("stack_combos", combo_or_list)
          names = Array(combo["presets"])
          weights = Array(combo["weights"])
          return names.each_with_index.filter_map do |preset_name, index|
            entry = resolve(preset_name)
            next unless entry

            entry.merge(weight: weights[index]&.to_f || entry[:motion_lora_weight])
          end
        end

        Array(combo_or_list).flat_map { |item| expand_stack_token(item) }
      end

      def training_defaults = load.fetch("training_defaults", {})

      def caption_for(preset_name, subject:)
        preset = load.dig("presets", preset_name.to_s) || {}
        template = preset["caption_template"].to_s
        return subject.to_s if template.empty?

        template.gsub("{subject}", subject.to_s)
      end

      def training_dir(preset_name, root: Master::ROOT)
        preset = load.dig("presets", preset_name.to_s) || {}
        base = training_defaults.fetch("dataset_root", "training_data")
        folder = preset["training_folder"] || preset_name.to_s
        File.expand_path(File.join(base, folder), root)
      end

      def apply!(opts, preset_name:)
        resolved = resolve(preset_name)
        return opts unless resolved

        apply_entries!(opts, [resolved])
      end

      def apply_stack!(opts, stack:)
        entries = resolve_stack(stack)
        return opts if entries.empty?

        apply_entries!(opts, entries)
      end

      def apply_entries!(opts, entries)
        primary = entries.first
        opts[:motion_lora] ||= primary[:motion_lora]
        opts[:motion_lora_weight] ||= primary[:weight] || primary[:motion_lora_weight]
        opts[:camera_phrase] = primary[:camera_phrase] if primary[:camera_phrase] && !primary[:camera_phrase].empty?

        extras = entries.drop(1)
        opts[:motion_loras] = (Array(opts[:motion_loras]) + extras).uniq { |e| e[:motion_lora] }
        opts
      end

      def expand_stack_token(token)
        token = token.to_s.strip
        return resolve_stack(token) if stack_names.include?(token)

        if names.include?(token)
          entry = resolve(token)
          return [entry.merge(weight: entry[:motion_lora_weight])] if entry
        end

        file, weight = token.split(":", 2)
        return [] if file.to_s.strip.empty?

        parsed_weight = weight.to_s.strip.empty? ? nil : weight.to_f
        [{ motion_lora: file.strip, motion_lora_weight: parsed_weight, weight: parsed_weight, camera_phrase: "" }]
      end

      def preset_entry(preset)
        {
          motion_lora: preset["lora_file"],
          motion_lora_weight: preset.fetch("inference_strength", 0.75).to_f,
          camera_phrase: preset["camera_phrase"].to_s,
          caption_template: preset["caption_template"],
          training_folder: preset["training_folder"],
        }
      end
    end
  end
end