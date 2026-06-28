# frozen_string_literal: true

require "fileutils"
require "json"

module Master
  module Reach
    # Bootstrap Motion LoRA training folders with short Flux+I2V clips + caption sidecars.
    module MotionLoraDataset
      class Error < StandardError; end

      module_function

      def bootstrap(
        preset:,
        subject:,
        clips: 12,
        backend: :kling,
        lora_id: nil,
        chunk_seconds: 6,
        root: Master::ROOT,
        replicate: nil
      )
        raise Error, "unknown preset: #{preset}" unless MotionLoraPresets.names.include?(preset.to_s)

        out_dir = MotionLoraPresets.training_dir(preset, root: root)
        FileUtils.mkdir_p(out_dir)
        caption = MotionLoraPresets.caption_for(preset, subject: subject)
        manifest = {
          preset: preset.to_s,
          subject: subject,
          caption: caption,
          backend: backend.to_s,
          clips: clips,
          generated: [],
        }

        clips.times do |index|
          prompt = "#{caption} — training clip #{index + 1} of #{clips}"
          result = VideoChain.generate(
            prompt: prompt,
            lora_id: lora_id,
            backend: backend,
            total_minutes: chunk_seconds / 60.0,
            chunk_seconds: chunk_seconds,
            max_threads: 1,
            output_dir: File.join(out_dir, "_gen"),
            temp_dir: File.join(out_dir, "_tmp"),
            replicate: replicate,
            root: root
          )
          dest = File.join(out_dir, format("clip_%03d.mp4", index + 1))
          FileUtils.cp(result[:path], dest)
          manifest[:generated] << { file: File.basename(dest), prompt: prompt }
        end

        File.write(File.join(out_dir, "captions.json"), JSON.pretty_generate(manifest))
        File.write(File.join(out_dir, "caption.txt"), caption)
        { dir: out_dir, clips: manifest[:generated].size, caption: caption }
      rescue VideoChain::Error => e
        raise Error, e.message
      end
    end
  end
end
