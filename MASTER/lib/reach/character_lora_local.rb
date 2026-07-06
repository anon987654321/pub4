# frozen_string_literal: true

require "fileutils"
require "json"

module Master
  module Reach
    # Local Flux character LoRA via ostris/ai-toolkit (same stack as Replicate's flux-dev-lora-trainer).
    module CharacterLoraLocal
      DEFAULT_STEPS = 1000
      DEFAULT_RANK = 32
      DEFAULT_LR = "1e-4"
      DEFAULT_CAPTION_DROPOUT = 0.05
      DEFAULT_VERSION = "v2"
      DEFAULT_MODEL = "black-forest-labs/FLUX.1-dev"
      DEFAULT_AI_TOOLKIT_ROOT = File.expand_path("~/ai-toolkit")

      class Error < StandardError; end

      module_function

      def bootstrap(
        name:,
        train_dir:,
        out_dir:,
        trigger_word:,
        steps: DEFAULT_STEPS,
        rank: DEFAULT_RANK,
        learning_rate: DEFAULT_LR,
        caption_dropout_rate: DEFAULT_CAPTION_DROPOUT,
        version: DEFAULT_VERSION,
        model: DEFAULT_MODEL,
        ai_toolkit_root: nil,
        subject: "woman"
      )
        toolkit_root = resolve_toolkit_root(ai_toolkit_root)
        config_dir = File.join(out_dir, "config")
        weights_dir = File.join(out_dir, "weights")
        FileUtils.mkdir_p(config_dir)
        FileUtils.mkdir_p(weights_dir)

        images = CharacterLoraZip.collect_images(train_dir)
        raise Error, "no images in #{train_dir}" if images.empty?

        config_name = "#{sanitize_name(name)}_#{sanitize_name(version)}"
        config_path = File.join(config_dir, "ai_toolkit.yaml")
        run_script = File.join(config_dir, "run_local.sh")
        train_abs = File.expand_path(train_dir)
        weights_abs = File.expand_path(weights_dir)

        File.write(config_path, build_config(
          name: config_name,
          dataset_dir: train_abs,
          weights_dir: weights_abs,
          trigger_word: trigger_word,
          steps: steps,
          rank: rank,
          learning_rate: learning_rate,
          caption_dropout_rate: caption_dropout_rate,
          model: model,
          subject: subject
        ))
        File.write(run_script, build_run_script(toolkit_root: toolkit_root))
        File.chmod(0o755, run_script)

        {
          mode: :local,
          name: name.to_s,
          config_name: config_name,
          trigger_word: trigger_word,
          toolkit_root: toolkit_root,
          train_dir: train_dir,
          config_path: config_path,
          run_script: run_script,
          weights_dir: weights_dir,
          images: images.size,
          steps: steps,
        }
      end

      def prepare_dataset(sources, dataset_dir, trigger_word:, subject: "woman")
        FileUtils.rm_rf(dataset_dir)
        FileUtils.mkdir_p(dataset_dir)
        images = Array(sources)
        images = CharacterLoraZip.collect_images(sources) unless sources.is_a?(Array)
        raise Error, "no images to stage" if images.empty?

        images.each_with_index.map do |src, index|
          ext = File.extname(src).downcase
          ext = ".jpg" if ext.empty?
          base = format("a_photo_of_%s_%02d", trigger_word, index + 1)
          dest = File.join(dataset_dir, "#{base}#{ext}")
          FileUtils.cp(src, dest)
          File.write(File.join(dataset_dir, "#{base}.txt"), descriptive_caption(src, trigger_word: trigger_word, subject: subject))
          dest
        end
      end

      def descriptive_caption(src, trigger_word:, subject:)
        dims = CharacterLoraZip.image_dimensions(src)
        crop = if dims
                 width, height = dims
                 ratio = width.to_f / height
                 if ratio < 0.8
                   "vertical portrait crop"
                 elsif ratio > 1.25
                   "horizontal environmental portrait"
                 else
                   "square portrait crop"
                 end
               else
                 "portrait crop"
               end
        frame = File.basename(src).match?(/frame|keyframe/) ? "video-derived still" : "source photograph"
        [
          trigger_word,
          subject,
          crop,
          frame,
          "natural expression",
          "realistic skin texture",
          "available light",
          "35mm candid photo",
        ].join(", ")
      end

      def resolve_toolkit_root(path)
        candidate = path.to_s.strip
        candidate = ENV["AI_TOOLKIT_ROOT"].to_s.strip if candidate.empty?
        candidate = DEFAULT_AI_TOOLKIT_ROOT if candidate.empty?
        File.expand_path(candidate)
      end

      def sanitize_name(name)
        name.to_s.downcase.gsub(/[^a-z0-9_-]/, "_").gsub(/_+/, "_").delete_prefix("_").delete_suffix("_")
      end

      def build_config(name:, dataset_dir:, weights_dir:, trigger_word:, steps:, rank:, learning_rate:, caption_dropout_rate:, model:, subject:)
        device = RUBY_PLATFORM.include?("darwin") ? "mps" : "cuda:0"
        <<~YAML
          ---
          job: extension
          config:
            name: "#{name}"
            process:
            - type: sd_trainer
              training_folder: "#{weights_dir}"
              device: #{device}
              trigger_word: "#{trigger_word}"
              network:
                type: lora
                linear: #{rank}
                linear_alpha: #{rank}
              save:
                dtype: float16
                save_every: 250
                max_step_saves_to_keep: 4
                push_to_hub: false
              datasets:
              - folder_path: "#{dataset_dir}"
                caption_ext: txt
                caption_dropout_rate: #{caption_dropout_rate}
                shuffle_tokens: false
                cache_latents_to_disk: true
                resolution: [512, 768, 1024]
              train:
                batch_size: 1
                steps: #{steps}
                gradient_accumulation_steps: 1
                train_unet: true
                train_text_encoder: false
                gradient_checkpointing: true
                noise_scheduler: flowmatch
                optimizer: adamw8bit
                lr: #{learning_rate}
                ema_config:
                  use_ema: true
                  ema_decay: 0.99
                dtype: bf16
              model:
                name_or_path: "#{model}"
                is_flux: true
                quantize: true
                low_vram: true
              sample:
                sampler: flowmatch
                sample_every: 250
                width: 1024
                height: 1024
                prompts:
                - "#{trigger_word}, #{subject}, portrait, natural light, detailed face"
                - "photo of #{trigger_word}, #{subject}, candid, soft background"
                - "#{trigger_word}, #{subject}, studio portrait, neutral backdrop"
                neg: ""
                seed: 42
                walk_seed: true
                guidance_scale: 4
                sample_steps: 20
              meta:
                name: "[name]"
                version: "1.0"
                master_trigger: "#{trigger_word}"
          meta:
            name: "[name]"
            version: "1.0"
        YAML
      end

      def build_run_script(toolkit_root:)
        <<~SCRIPT
          #!/bin/sh
          set -e
          HERE="$(cd "$(dirname "$0")/.." && pwd)"
          ROOT="${AI_TOOLKIT_ROOT:-#{toolkit_root}}"
          CONFIG="$HERE/config/ai_toolkit.yaml"
          LOG="$HERE/weights/train.log"
          if [ ! -d "$ROOT" ]; then
            echo "ai-toolkit not found at $ROOT" >&2
            echo "clone: git clone https://github.com/ostris/ai-toolkit.git $ROOT" >&2
            exit 1
          fi
          cd "$ROOT"
          if [ -f .venv/bin/activate ]; then
            . .venv/bin/activate
          elif [ -f venv/bin/activate ]; then
            . venv/bin/activate
          fi
          TOKEN="${HF_TOKEN:-${HUGGING_FACE_HUB_TOKEN:-}}"
          if [ -n "$TOKEN" ]; then
            export HF_TOKEN="$TOKEN"
            export HUGGING_FACE_HUB_TOKEN="$TOKEN"
            hf auth login --token "$TOKEN" >/dev/null 2>&1 || true
          fi
          if ! hf auth whoami >/dev/null 2>&1; then
            echo "Hugging Face auth required for black-forest-labs/FLUX.1-dev (gated model)." >&2
            echo "1. Accept license: https://huggingface.co/black-forest-labs/FLUX.1-dev" >&2
            echo "2. Create token: https://huggingface.co/settings/tokens (Read access)" >&2
            echo "3. export HF_TOKEN=hf_... && sh $0" >&2
            exit 1
          fi
          mkdir -p "$(dirname "$LOG")"
          exec python run.py "$CONFIG" 2>&1 | tee "$LOG"
        SCRIPT
      end

      def format_notes(result)
        [
          "local: ostris/ai-toolkit (no Replicate)",
          "train: #{result[:train_dir]}",
          "config: #{result[:config_path]}",
          "run: #{result[:run_script]}",
          "weights: #{result[:weights_dir]}/#{result[:config_name]}/",
          "toolkit: #{result[:toolkit_root]} (override with AI_TOOLKIT_ROOT)",
          "comfyui: copy final .safetensors → ComfyUI/models/loras/",
        ]
      end
    end
  end
end
