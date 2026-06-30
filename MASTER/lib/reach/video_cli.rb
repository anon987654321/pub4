# frozen_string_literal: true

module Master
  module Reach
    # Shared argument parsing + execution for /video CLI and bin/video.
    module VideoCli
      module_function

      def parse_video_args(raw)
        tokens = raw.to_s.strip.split(/\s+/)
        return { usage: video_usage } if tokens.empty?

        backend = :kling
        minutes = 2.0
        seconds = nil
        critique = false
        vision_critique = false
        per_chunk_critique = nil
        auto_retry_weak = false
        max_weak_retries = 2
        lora_id = nil
        motion_lora = nil
        motion_lora_weight = nil
        motion_loras = []
        motion_preset = nil
        video_format = :cinematic
        camera_plan = :dolly
        continuity = :anchored
        grade_preset = nil
        final_grade = true
        offer = nil
        cta_label = nil
        cta_url = nil
        aspect_ratio = "16:9"
        fps = 24
        chunk_seconds = 10
        prompt_tokens = []

        until tokens.empty?
          token = tokens.shift
          case token
          when "--backend" then backend = (tokens.shift || "kling").to_sym
          when "--minutes" then minutes = (tokens.shift || "2").to_f
          when "--seconds" then seconds = (tokens.shift || "0").to_f
          when "--chunk-seconds" then chunk_seconds = (tokens.shift || "10").to_i
          when "--format" then video_format = (tokens.shift || "cinematic").to_sym
          when "--camera-plan" then camera_plan = (tokens.shift || "dolly").to_sym
          when "--continuity" then continuity = (tokens.shift || "anchored").to_sym
          when "--grade" then grade_preset = tokens.shift
          when "--no-final-grade" then final_grade = false
          when "--offer" then offer = tokens.shift
          when "--cta" then cta_label = tokens.shift
          when "--cta-url" then cta_url = tokens.shift
          when "--aspect" then aspect_ratio = tokens.shift || "16:9"
          when "--fps" then fps = (tokens.shift || "24").to_i
          when "--critique" then critique = true
          when "--vision-critique" then vision_critique = true
          when "--per-chunk-critique" then per_chunk_critique = true
          when "--no-per-chunk-critique" then per_chunk_critique = false
          when "--auto-retry" then auto_retry_weak = true
          when "--max-retries" then max_weak_retries = (tokens.shift || "2").to_i
          when "--lora" then lora_id = tokens.shift
          when "--motion-lora" then motion_lora = tokens.shift
          when "--motion-weight" then motion_lora_weight = (tokens.shift || "0.75").to_f
          when "--motion-stack" then motion_loras = (tokens.shift || "").split(",").map(&:strip).reject(&:empty?)
          when "--motion-preset" then motion_preset = tokens.shift
          else prompt_tokens << token
          end
        end

        prompt = prompt_tokens.join(" ").strip
        return { usage: video_usage } if prompt.empty?

        vision_critique = true if critique && ENV["MOTION_CRITIQUE_VISION"].to_s == "1" && !vision_critique

        {
          backend: backend,
          minutes: minutes,
          seconds: seconds,
          chunk_seconds: chunk_seconds,
          video_format: video_format,
          camera_plan: camera_plan,
          continuity: continuity,
          grade_preset: grade_preset,
          final_grade: final_grade,
          offer: offer,
          cta_label: cta_label,
          cta_url: cta_url,
          aspect_ratio: aspect_ratio,
          fps: fps,
          critique: critique,
          vision_critique: vision_critique,
          per_chunk_critique: per_chunk_critique,
          auto_retry_weak: auto_retry_weak,
          max_weak_retries: max_weak_retries,
          lora_id: lora_id,
          motion_lora: motion_lora,
          motion_lora_weight: motion_lora_weight,
          motion_loras: motion_loras,
          motion_preset: motion_preset,
          prompt: prompt,
        }
      end

      def parse_motion_dataset_args(raw)
        tokens = raw.to_s.strip.split(/\s+/)
        return { usage: motion_dataset_usage } if tokens.empty?

        preset = nil
        subject = nil
        clips = 12
        backend = :kling
        lora_id = nil

        until tokens.empty?
          token = tokens.shift
          case token
          when "--preset" then preset = tokens.shift
          when "--subject" then subject = tokens.shift
          when "--clips" then clips = (tokens.shift || "12").to_i
          when "--backend" then backend = (tokens.shift || "kling").to_sym
          when "--lora" then lora_id = tokens.shift
          else
            subject ||= token
            preset ||= token
          end
        end

        return { usage: motion_dataset_usage } if preset.to_s.empty? || subject.to_s.empty?

        { preset: preset, subject: subject, clips: clips, backend: backend, lora_id: lora_id }
      end

      def run_generate(parsed, root: Master::ROOT, agent: nil, event_bus: nil)
        result = VideoChain.generate(
          prompt: parsed[:prompt],
          lora_id: parsed[:lora_id],
          backend: parsed[:backend],
          total_minutes: parsed[:minutes],
          total_seconds: parsed[:seconds],
          chunk_seconds: parsed[:chunk_seconds],
          video_format: parsed[:video_format],
          camera_plan: parsed[:camera_plan],
          continuity: parsed[:continuity],
          grade_preset: parsed[:grade_preset],
          final_grade: parsed[:final_grade],
          offer: parsed[:offer],
          cta_label: parsed[:cta_label],
          cta_url: parsed[:cta_url],
          aspect_ratio: parsed[:aspect_ratio],
          fps: parsed[:fps],
          motion_lora: parsed[:motion_lora],
          motion_lora_weight: parsed[:motion_lora_weight],
          motion_loras: parsed[:motion_loras],
          motion_preset: parsed[:motion_preset],
          critique: parsed[:critique],
          vision_critique: parsed[:vision_critique],
          per_chunk_critique: parsed[:per_chunk_critique],
          auto_retry_weak: parsed[:auto_retry_weak],
          max_weak_retries: parsed[:max_weak_retries],
          agent: agent,
          event_bus: event_bus,
          root: root
        )
        format_result(parsed, result)
      rescue VideoChain::Error => e
        "video: #{e.message}"
      end

      def format_result(parsed, result)
        lines = [
          "video: backend=#{parsed[:backend]} seconds=#{parsed[:seconds] || (parsed[:minutes] * 60.0)} format=#{parsed[:video_format]} camera=#{parsed[:camera_plan]} continuity=#{parsed[:continuity]}",
          "prompt: #{parsed[:prompt][0, 120]}...",
          "output: #{result[:path]}",
          "manifest: #{result[:manifest]}",
        ]
        if result[:critique]
          mode = result[:critique][:mode] || :text
          score = result[:critique][:overall_score] || result[:critique][:score]
          flagged = result[:critique][:flagged_chunks] || result[:critique][:weak_chunks] || []
          lines << "council(#{mode}): score=#{score}/10 passed=#{result[:critique][:passed]}"
          lines << "flagged_chunks: #{flagged.join(', ')}" if flagged.any?
          if result[:critique][:chunk_critiques]&.any?
            chunk_lines = result[:critique][:chunk_critiques].map do |entry|
              "scene #{entry[:scene]}=#{entry[:score]}/10"
            end
            lines << "per_chunk: #{chunk_lines.join(', ')}"
          end
          if result[:critique][:whole_video]
            whole = result[:critique][:whole_video]
            whole_score = whole[:overall_score] || whole[:score]
            lines << "whole_video: score=#{whole_score}/10 passed=#{whole[:passed]}"
          end
        end
        if result[:regenerated]&.any?
          details = result[:regenerated].map { |entry| "scene #{entry[:scene]}@attempt#{entry[:attempt]}" }.join(", ")
          lines << "regenerated: #{details}"
        end
        lines << "retried_chunks: #{result[:retried_chunks]}" if result[:retried_chunks].to_i.positive?
        lines.join("\n")
      end

      def video_usage
        presets = MotionLoraPresets.names.join("|")
        "usage: video [--backend kling|happyhorse|cogvideox|minimax|animatediff|animatediff_camera] " \
          "[--minutes N|--seconds N] [--chunk-seconds N] [--format commercial|direct_response|ugc|infomercial|editorial|cinematic] " \
          "[--camera-plan locked|handheld|dolly|orbit|product|social] [--continuity loose|anchored|strict] " \
          "[--offer TEXT] [--cta TEXT] [--cta-url URL] [--grade commercial|infomercial|beauty|analog|cinematic] " \
          "[--no-final-grade] [--aspect 16:9|9:16|4:5|1:1] [--fps 24] " \
          "[--critique] [--vision-critique] [--per-chunk-critique] [--auto-retry] " \
          "[--max-retries N] [--lora ID] " \
          "[--motion-lora FILE] [--motion-stack preset1,preset2] [--motion-preset #{presets}] " \
          "[--motion-weight 0.75] <prompt>"
      end

      def motion_dataset_usage
        presets = MotionLoraPresets.names.join("|")
        "usage: motion-dataset --preset #{presets} --subject \"character description\" " \
          "[--clips 12] [--backend kling] [--lora ID]"
      end

      def parse_lora_train_args(raw)
        tokens = shell_split(raw.to_s.strip)
        return { usage: lora_train_usage } if tokens.empty?

        name = nil
        destination = nil
        trigger_word = nil
        split_videos = true
        frames_per_video = nil
        max_images = CharacterLoraDataset::RECOMMENDED_MAX
        min_images = CharacterLoraDataset::RECOMMENDED_MIN
        use_all_frames = false
        curation_strategy = :ranked
        max_per_source = nil
        min_frame_gap = nil
        prepare_only = false
        local = false
        ai_toolkit_root = nil
        steps = CharacterLoraLocal::DEFAULT_STEPS
        rank = CharacterLoraLocal::DEFAULT_RANK
        learning_rate = CharacterLoraLocal::DEFAULT_LR
        caption_dropout_rate = CharacterLoraLocal::DEFAULT_CAPTION_DROPOUT
        version = CharacterLoraLocal::DEFAULT_VERSION
        subject = "woman"
        exclude = []
        sources = []

        until tokens.empty?
          token = tokens.shift
          case token
          when "--name" then name = tokens.shift
          when "--destination" then destination = tokens.shift
          when "--trigger" then trigger_word = tokens.shift
          when "--split-all", "--split-frames" then split_videos = true
          when "--no-split" then split_videos = false
          when "--frames-per-video" then frames_per_video = (tokens.shift || "8").to_i
          when "--max-images" then max_images = (tokens.shift || "18").to_i
          when "--min-images" then min_images = (tokens.shift || "12").to_i
          when "--use-all-frames" then use_all_frames = true
          when "--curation" then curation_strategy = (tokens.shift || "ranked").to_sym
          when "--max-per-source" then max_per_source = (tokens.shift || "0").to_i
          when "--min-frame-gap" then min_frame_gap = (tokens.shift || "0").to_i
          when "--prepare-only" then prepare_only = true
          when "--local" then local = true
          when "--ai-toolkit" then ai_toolkit_root = tokens.shift
          when "--steps" then steps = (tokens.shift || "1000").to_i
          when "--rank" then rank = (tokens.shift || "16").to_i
          when "--lr" then learning_rate = tokens.shift || CharacterLoraLocal::DEFAULT_LR
          when "--caption-dropout" then caption_dropout_rate = (tokens.shift || CharacterLoraLocal::DEFAULT_CAPTION_DROPOUT).to_f
          when "--version" then version = tokens.shift || CharacterLoraLocal::DEFAULT_VERSION
          when "--subject" then subject = tokens.shift
          when "--exclude" then exclude << tokens.shift
          else sources << token
          end
        end

        return { usage: lora_train_usage } if name.to_s.empty? || sources.empty?

        trigger_word = trigger_word.to_s.strip
        trigger_word = name.to_s if trigger_word.empty?

        {
          name: name,
          destination: destination,
          trigger_word: trigger_word,
          split_videos: split_videos,
          frames_per_video: frames_per_video,
          max_images: max_images,
          min_images: min_images,
          use_all_frames: use_all_frames,
          curation_strategy: curation_strategy,
          max_per_source: max_per_source,
          min_frame_gap: min_frame_gap,
          prepare_only: prepare_only,
          local: local,
          ai_toolkit_root: ai_toolkit_root,
          steps: steps,
          rank: rank,
          learning_rate: learning_rate,
          caption_dropout_rate: caption_dropout_rate,
          version: version,
          subject: subject,
          exclude: exclude.compact,
          sources: sources,
        }
      end

      def run_lora_train(parsed, root: Master::ROOT)
        result = CharacterLoraTrain.train(
          name: parsed[:name],
          sources: parsed[:sources],
          destination: parsed[:destination],
          trigger_word: parsed[:trigger_word],
          split_videos: parsed[:split_videos],
          frames_per_video: parsed[:frames_per_video],
          max_images: parsed[:max_images],
          min_images: parsed[:min_images],
          use_all_frames: parsed[:use_all_frames],
          curation_strategy: parsed[:curation_strategy],
          max_per_source: parsed[:max_per_source],
          min_frame_gap: parsed[:min_frame_gap],
          exclude: parsed[:exclude],
          prepare_only: parsed[:prepare_only],
          local: parsed[:local],
          ai_toolkit_root: parsed[:ai_toolkit_root],
          steps: parsed[:steps],
          rank: parsed[:rank],
          learning_rate: parsed[:learning_rate],
          caption_dropout_rate: parsed[:caption_dropout_rate],
          version: parsed[:version],
          subject: parsed[:subject],
          root: root
        )
        CharacterLoraTrain.format_result(result)
      rescue CharacterLoraTrain::Error => e
        "lora-train: #{e.message}"
      end

      def shell_split(raw)
        raw.scan(/(?:[^\s"']+|"[^"]*"|'[^']*')+/).map { |token| token.delete_prefix('"').delete_suffix('"').delete_prefix("'").delete_suffix("'") }
      end

      def lora_train_usage
        "usage: lora-train --name ragnhild [--destination owner/model] [--trigger ragnhild] " \
          "[--local] [--ai-toolkit ~/ai-toolkit] [--steps 1000] [--rank 32] [--lr 1e-4] " \
          "[--caption-dropout 0.05] [--version v2] [--subject woman] [--split-all] [--curation ranked|even] " \
          "[--max-images 70] [--max-per-source N] [--min-frame-gap N] [--use-all-frames] [--frames-per-video N] " \
          "[--prepare-only] [--exclude path] <image-or-video> [...]"
      end
    end
  end
end
