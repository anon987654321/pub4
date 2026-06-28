# frozen_string_literal: true

require "fileutils"
require "securerandom"

module Master
  module Reach
    # Pluggable cinematic video pipeline: Flux keyframe → I2V backend → analog post → stitch.
    class VideoChain
      class Error < StandardError; end

      FLUX_MODEL = "black-forest-labs/flux-1.1-pro"
      BACKENDS = {
        kling: { provider: :replicate, version: "kwaivgi/kling-v2.1", max_duration: 10 },
        happyhorse: { provider: :replicate, version: "minimax/video-01-live", max_duration: 12 },
        cogvideox: { provider: :replicate, version: "thudm/cogvideox-5b-i2v", max_duration: 10 },
        minimax: { provider: :replicate, version: "minimax/video-01-live", max_duration: 12 },
        animatediff: { provider: :comfyui, max_duration: 16, frames: 81 },
        animatediff_camera: { provider: :comfyui, max_duration: 16, frames: 81 },
        comfyui_local: { provider: :comfyui, max_duration: 16, frames: 81 },
      }.freeze

      def self.generate(
        prompt:,
        lora_id: nil,
        backend: :kling,
        total_minutes: 2,
        chunk_seconds: 10,
        output_dir: "output/cinematic",
        temp_dir: "tmp/video_chain",
        grain_intensity: 18,
        vignette: "PI/4",
        max_threads: 4,
        motion_intensity: 0.75,
        motion_lora: nil,
        motion_lora_weight: nil,
        motion_loras: [],
        motion_preset: nil,
        critique: false,
        vision_critique: false,
        per_chunk_critique: nil,
        auto_retry_weak: false,
        max_weak_retries: 2,
        agent: nil,
        event_bus: nil,
        replicate: nil,
        comfyui: nil,
        root: Master::ROOT
      )
        new(
          root: root,
          agent: agent,
          event_bus: event_bus,
          replicate: replicate || ReplicateClient.new,
          comfyui: comfyui
        ).generate(
          prompt: prompt,
          lora_id: lora_id,
          backend: backend,
          total_minutes: total_minutes,
          chunk_seconds: chunk_seconds,
          output_dir: output_dir,
          temp_dir: temp_dir,
          grain_intensity: grain_intensity,
          vignette: vignette,
          max_threads: max_threads,
          motion_intensity: motion_intensity,
          motion_lora: motion_lora,
          motion_lora_weight: motion_lora_weight,
          motion_loras: motion_loras,
          motion_preset: motion_preset,
          critique: critique,
          vision_critique: vision_critique,
          per_chunk_critique: per_chunk_critique,
          auto_retry_weak: auto_retry_weak,
          max_weak_retries: max_weak_retries
        )
      end

      def initialize(root:, replicate:, comfyui: nil, agent: nil, event_bus: nil)
        @root = root
        @replicate = replicate
        @comfyui = comfyui
        @agent = agent
        @bus = event_bus
      end

      def generate(**kwargs)
        opts = normalize_options(kwargs)
        FileUtils.mkdir_p([opts[:temp_dir], opts[:output_dir]])
        total_chunks = (opts[:total_minutes] * 60.0 / opts[:chunk_seconds]).ceil
        log("Starting #{opts[:total_minutes]} min (#{total_chunks} chunks) | backend=#{opts[:backend]}")
        @bus&.publish(:video_chain_start, backend: opts[:backend], chunks: total_chunks)

        clips = generate_chunks(opts, total_chunks)
        final_path = stitch(clips, opts)
        critique_result = nil
        regenerated = []
        retry_count = 0

        if opts[:critique] || opts[:auto_retry_weak]
          loop do
            critique_result = run_critique(final_path, opts, clips: clips)
            log_critique(critique_result, per_chunk: opts[:per_chunk_critique])
            break unless opts[:auto_retry_weak] &&
                         flagged_chunks(critique_result).any? &&
                         retry_count < opts[:max_weak_retries]

            retry_count += 1
            boosted = [opts[:motion_intensity] + (0.1 * retry_count), 0.95].min
            indices = chunk_indices_from_flagged(flagged_chunks(critique_result), clips.size)
            log("Auto re-generating #{indices.size} weak chunks (attempt #{retry_count}, motion=#{boosted.round(2)})")

            indices.each do |idx|
              log("  → Re-generating chunk #{idx} (scene #{idx + 1})")
              clips[idx] = render_chunk(idx, total_chunks, opts.merge(motion_intensity: boosted))
              regenerated << { chunk: idx, scene: idx + 1, attempt: retry_count }
              @bus&.publish(:video_chain_retry_chunk, chunk: idx, scene: idx + 1, attempt: retry_count)
            end

            final_path = stitch(clips, opts, retry_label: "retry#{retry_count}")
          end

          if opts[:critique] && opts[:per_chunk_critique]
            whole = run_whole_critique(final_path, opts)
            critique_result = critique_result.merge(whole_video: whole) if critique_result
          end
        end

        log("Final video ready → #{final_path}")
        @bus&.publish(:video_chain_done, path: final_path, critique: critique_result, regenerated: regenerated)
        {
          path: final_path,
          critique: critique_result,
          retried_chunks: regenerated.size,
          regenerated: regenerated,
        }
      rescue ArgumentError => e
        raise Error, e.message
      end

      private

      def normalize_options(kwargs)
        backend = kwargs.fetch(:backend, :kling).to_sym
        backend = :animatediff if backend == :comfyui_local
        config = BACKENDS.fetch(backend) { BACKENDS[:kling] }
        weight = kwargs[:motion_lora_weight]
        weight = ENV["COMFYUI_MOTION_LORA_WEIGHT"] if weight.nil?
        weight = weight.to_f if weight
        weight ||= 0.75
        opts = {
          prompt: kwargs.fetch(:prompt),
          lora_id: kwargs[:lora_id],
          backend: backend,
          config: config,
          total_minutes: kwargs.fetch(:total_minutes, 2).to_f,
          chunk_seconds: kwargs.fetch(:chunk_seconds, 10).to_i,
          output_dir: expand(kwargs.fetch(:output_dir, "output/cinematic")),
          temp_dir: expand(kwargs.fetch(:temp_dir, "tmp/video_chain")),
          grain_intensity: kwargs.fetch(:grain_intensity, 18).to_i,
          vignette: kwargs.fetch(:vignette, "PI/4").to_s,
          max_threads: [kwargs.fetch(:max_threads, 4).to_i, 1].max,
          motion_intensity: kwargs.fetch(:motion_intensity, 0.75).to_f,
          motion_lora: kwargs[:motion_lora] || ENV["COMFYUI_MOTION_LORA"],
          motion_lora_weight: weight,
          motion_lora_2: nil,
          motion_lora_2_weight: nil,
          camera_phrase: nil,
          motion_preset: kwargs[:motion_preset],
          motion_loras: Array(kwargs[:motion_loras]).map(&:to_s).reject(&:empty?),
          critique: kwargs.fetch(:critique, false),
          vision_critique: kwargs.fetch(:vision_critique, false),
          per_chunk_critique: per_chunk_critique_default(kwargs),
          auto_retry_weak: kwargs.fetch(:auto_retry_weak, false),
          max_weak_retries: [kwargs.fetch(:max_weak_retries, 2).to_i, 0].max,
        }
        apply_motion_loras!(opts)
        split_stacked_motion_loras!(opts)
        opts[:prompt] = "#{opts[:prompt]}, #{opts[:camera_phrase]}" if opts[:camera_phrase] && !opts[:camera_phrase].empty?
        opts
      end

      def apply_motion_loras!(opts)
        MotionLoraPresets.apply!(opts, preset_name: opts[:motion_preset]) if opts[:motion_preset]
        return if opts[:motion_loras].empty?

        resolved = opts[:motion_loras].filter_map { |name| MotionLoraPresets.resolve(name) }
        return if resolved.empty?

        opts[:motion_lora] ||= resolved[0][:motion_lora]
        opts[:motion_lora_weight] ||= resolved[0][:motion_lora_weight]
        opts[:motion_lora_2] ||= resolved[1]&.dig(:motion_lora) || resolved[0][:stack_lora]
        opts[:motion_lora_2_weight] ||= resolved[1]&.dig(:motion_lora_weight) || resolved[0][:stack_strength]
        phrases = resolved.map { |entry| entry[:camera_phrase] }.reject(&:empty?)
        opts[:camera_phrase] = phrases.join(", ") unless phrases.empty?
      end

      def split_stacked_motion_loras!(opts)
        return unless opts[:motion_lora].to_s.include?(",")

        primary, secondary = opts[:motion_lora].split(",", 2).map(&:strip)
        opts[:motion_lora] = primary
        opts[:motion_lora_2] ||= secondary
      end

      def expand(path) = File.expand_path(path, @root)

      def generate_chunks(opts, total_chunks)
        queue = Queue.new
        (0...total_chunks).each { |idx| queue << idx }
        results = Array.new(total_chunks)
        workers = Array.new([opts[:max_threads], total_chunks].min) do
          Thread.new do
            loop do
              idx = queue.pop(true)
              results[idx] = render_chunk(idx, total_chunks, opts)
            rescue ThreadError
              break
            end
          end
        end
        workers.each(&:join)
        results
      end

      def render_chunk(idx, total_chunks, opts)
        scene_prompt = build_scene_prompt(opts[:prompt], idx, total_chunks)
        keyframe_url = flux_keyframe(scene_prompt, opts[:lora_id])
        clip_url = i2v_clip(keyframe_url, scene_prompt, opts)
        raw_path = File.join(opts[:temp_dir], format("raw_%03d.mp4", idx))
        VideoPost.download_url(clip_url, raw_path)
        VideoPost.apply_analog_filter(raw_path, grain: opts[:grain_intensity], vignette: opts[:vignette])
      end

      def build_scene_prompt(base, idx, total)
        "#{base} — scene #{idx + 1} of #{total}, cinematic composition, dramatic lighting, " \
          "analog 35mm film look, deep depth of field, consistent character identity"
      end

      def flux_keyframe(scene_prompt, lora_id)
        input = {
          prompt: scene_prompt,
          aspect_ratio: "16:9",
          output_format: "png",
          output_quality: 95,
        }
        input[:lora] = lora_id if lora_id && !lora_id.to_s.strip.empty?
        first_output(@replicate.predict(FLUX_MODEL, input))
      end

      def i2v_clip(keyframe_url, scene_prompt, opts)
        return comfyui_i2v(keyframe_url, scene_prompt, opts) if opts[:config][:provider] == :comfyui

        replicate_i2v(keyframe_url, scene_prompt, opts)
      end

      def replicate_i2v(keyframe_url, scene_prompt, opts)
        duration = [opts[:chunk_seconds], opts[:config][:max_duration]].min
        input = {
          image: keyframe_url,
          prompt: scene_prompt,
          duration: duration,
          motion_intensity: opts[:motion_intensity],
          fps: 24,
        }
        first_output(@replicate.predict(opts[:config][:version], input))
      end

      def comfyui_i2v(keyframe_url, scene_prompt, opts)
        frames = [opts[:chunk_seconds] * 8, opts[:config][:frames]].min
        comfyui_client.i2v(
          keyframe_url: keyframe_url,
          prompt: scene_prompt,
          frames: frames,
          motion_lora: opts[:motion_lora],
          motion_weight: opts[:motion_lora_weight],
          motion_lora_2: opts[:motion_lora_2],
          motion_lora_2_weight: opts[:motion_lora_2_weight]
        )
      end

      def comfyui_client
        @comfyui ||= ComfyuiClient.new
      end

      def first_output(output)
        url = Array(output).flatten.first
        raise Error, "empty model output" if url.to_s.strip.empty?

        url.to_s
      end

      def stitch(clips, opts, retry_label: nil)
        stamp = Time.now.strftime("%Y%m%d_%H%M")
        name = if retry_label
                 "cinematic_#{opts[:backend]}_#{retry_label}_#{SecureRandom.hex(4)}.mp4"
               else
                 "cinematic_#{opts[:backend]}_#{SecureRandom.hex(6)}_#{stamp}.mp4"
               end
        final_path = File.join(opts[:output_dir], name)
        VideoPost.concat_clips(clips, final_path)
      end

      def per_chunk_critique_default(kwargs)
        explicit = kwargs[:per_chunk_critique]
        return explicit unless explicit.nil?

        kwargs.fetch(:auto_retry_weak, false) || ENV["MOTION_CRITIQUE_PER_CHUNK"].to_s == "1"
      end

      def run_critique(final_path, opts, clips: nil)
        vision = vision_critique_enabled?(opts)
        if opts[:per_chunk_critique] && clips
          return Judge::Council::MotionCritique.critique_chunks(
            clips: clips,
            original_prompt: opts[:prompt],
            agent: @agent,
            event_bus: @bus,
            vision: vision
          )
        end

        run_whole_critique(final_path, opts)
      end

      def run_whole_critique(final_path, opts)
        Judge::Council::MotionCritique.critique(
          final_path,
          opts[:prompt],
          agent: @agent,
          event_bus: @bus,
          vision: vision_critique_enabled?(opts)
        )
      end

      def vision_critique_enabled?(opts)
        opts[:vision_critique] || (opts[:critique] && ENV["MOTION_CRITIQUE_VISION"].to_s == "1")
      end

      def flagged_chunks(critique_result)
        return [] unless critique_result

        Array(critique_result[:flagged_chunks] || critique_result[:weak_chunks])
      end

      def chunk_indices_from_flagged(flagged, clip_count)
        nums = Array(flagged).map(&:to_i).uniq.sort
        return [] if nums.empty?

        indices = nums.any?(&:zero?) ? nums : nums.map { |num| num - 1 }
        indices.select { |idx| idx >= 0 && idx < clip_count }
      end

      def log(message) = $stderr.puts("[VideoChain] #{message}")

      def log_critique(critique_result, per_chunk: false)
        flagged = flagged_chunks(critique_result)
        score = critique_result[:overall_score] || critique_result[:score]
        label = per_chunk ? "Per-chunk council" : "MotionCouncil"
        log("#{label} score: #{score}/10 | flagged scenes: #{flagged.empty? ? 'none' : flagged.join(', ')}")
        return unless per_chunk && critique_result[:chunk_critiques]

        critique_result[:chunk_critiques].each do |entry|
          status = entry[:passed] ? "pass" : "FAIL"
          log("  scene #{entry[:scene]}: #{entry[:score]}/10 [#{status}]")
        end
      end
    end
  end
end