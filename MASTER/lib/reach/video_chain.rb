# frozen_string_literal: true

require "fileutils"
require "json"
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
      VIDEO_FORMATS = {
        commercial: {
          grade: "commercial",
          beats: [
            "opening hook, immediate visual intrigue, product-world atmosphere",
            "hero beauty shot, premium lighting, memorable product or person reveal",
            "use-case demonstration, tactile details, credible human moment",
            "benefit proof, social texture, aspirational but believable scene",
            "closing brand image, clear call to action, polished end-frame energy",
          ],
        },
        infomercial: {
          grade: "infomercial",
          beats: [
            "relatable problem setup, clear before-state, documentary clarity",
            "solution reveal, confident presenter-like composition, bright practical lighting",
            "demonstration sequence, step-by-step visual proof, easy-to-read action",
            "benefit recap, testimonial feeling, optimistic everyday realism",
            "offer and call-to-action close, simple composition, broadcast polish",
          ],
        },
        editorial: {
          grade: "beauty",
          beats: [
            "quiet cinematic introduction, atmosphere and texture",
            "intimate portrait or product detail, shallow depth of field",
            "movement through environment, natural gesture, editorial composition",
            "emotional close-up, soft light, analog beauty",
            "final iconic frame, restrained brand mood",
          ],
        },
        cinematic: {
          grade: "cinematic",
          beats: [
            "establishing shot, cinematic geography, strong mood",
            "character or object reveal, dramatic light and shadow",
            "motivated movement, camera glides through the scene",
            "heightened detail shot, atmosphere and story texture",
            "resolving final image, memorable composition",
          ],
        },
      }.freeze

      def self.generate(
        prompt:,
        lora_id: nil,
        backend: :kling,
        total_minutes: 2,
        total_seconds: nil,
        chunk_seconds: 10,
        output_dir: "output/cinematic",
        temp_dir: "tmp/video_chain",
        grain_intensity: 18,
        vignette: "PI/4",
        final_grade: true,
        grade_preset: nil,
        video_format: :cinematic,
        aspect_ratio: "16:9",
        fps: 24,
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
          total_seconds: total_seconds,
          chunk_seconds: chunk_seconds,
          output_dir: output_dir,
          temp_dir: temp_dir,
          grain_intensity: grain_intensity,
          vignette: vignette,
          final_grade: final_grade,
          grade_preset: grade_preset,
          video_format: video_format,
          aspect_ratio: aspect_ratio,
          fps: fps,
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
        total_chunks = (opts[:total_seconds] / opts[:chunk_seconds]).ceil
        log("Starting #{opts[:total_seconds].round(1)} sec (#{total_chunks} chunks) | backend=#{opts[:backend]} format=#{opts[:video_format]}")
        @bus&.publish(:video_chain_start, backend: opts[:backend], chunks: total_chunks)

        scene_prompts = build_scene_prompts(opts, total_chunks)
        clips = generate_chunks(opts, total_chunks, scene_prompts)
        final_path = stitch(clips, opts)
        final_path = grade_final(final_path, opts)
        manifest_path = write_manifest(final_path, opts, clips, scene_prompts)
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
              clips[idx] = render_chunk(idx, total_chunks, opts.merge(motion_intensity: boosted), scene_prompts[idx])
              regenerated << { chunk: idx, scene: idx + 1, attempt: retry_count }
              @bus&.publish(:video_chain_retry_chunk, chunk: idx, scene: idx + 1, attempt: retry_count)
            end

            final_path = stitch(clips, opts, retry_label: "retry#{retry_count}")
            final_path = grade_final(final_path, opts, retry_label: "retry#{retry_count}")
            manifest_path = write_manifest(final_path, opts, clips, scene_prompts, regenerated: regenerated)
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
          manifest: manifest_path,
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
          total_seconds: normalize_total_seconds(kwargs),
          chunk_seconds: kwargs.fetch(:chunk_seconds, 10).to_i,
          output_dir: expand(kwargs.fetch(:output_dir, "output/cinematic")),
          temp_dir: expand(kwargs.fetch(:temp_dir, "tmp/video_chain")),
          grain_intensity: kwargs.fetch(:grain_intensity, 18).to_i,
          vignette: kwargs.fetch(:vignette, "PI/4").to_s,
          final_grade: kwargs.fetch(:final_grade, true),
          grade_preset: kwargs[:grade_preset],
          video_format: normalize_video_format(kwargs[:video_format]),
          aspect_ratio: kwargs.fetch(:aspect_ratio, "16:9").to_s,
          fps: kwargs.fetch(:fps, 24).to_i,
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
        apply_format_defaults!(opts)
        opts[:prompt] = "#{opts[:prompt]}, #{opts[:camera_phrase]}" if opts[:camera_phrase] && !opts[:camera_phrase].empty?
        opts[:width], opts[:height] = dimensions_for(opts[:aspect_ratio])
        opts
      end

      def normalize_total_seconds(kwargs)
        seconds = kwargs[:total_seconds]
        seconds = kwargs[:seconds] if seconds.nil?
        seconds = seconds.to_f if seconds
        seconds = kwargs.fetch(:total_minutes, 2).to_f * 60.0 if seconds.nil? || seconds <= 0
        seconds
      end

      def normalize_video_format(format)
        value = format.to_s.strip
        value = "cinematic" if value.empty?
        VIDEO_FORMATS.key?(value.to_sym) ? value.to_sym : :cinematic
      end

      def apply_format_defaults!(opts)
        format = VIDEO_FORMATS.fetch(opts[:video_format])
        opts[:grade_preset] ||= format[:grade]
        opts[:chunk_seconds] = [opts[:chunk_seconds], opts[:config][:max_duration]].min
        opts[:chunk_seconds] = 8 if opts[:chunk_seconds] <= 0
      end

      def dimensions_for(aspect_ratio)
        case aspect_ratio
        when "9:16" then [1080, 1920]
        when "4:5" then [1080, 1350]
        when "1:1" then [1080, 1080]
        else [1920, 1080]
        end
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

      def build_scene_prompts(opts, total_chunks)
        (0...total_chunks).map { |idx| build_scene_prompt(opts[:prompt], idx, total_chunks, opts) }
      end

      def generate_chunks(opts, total_chunks, scene_prompts)
        queue = Queue.new
        (0...total_chunks).each { |idx| queue << idx }
        results = Array.new(total_chunks)
        workers = Array.new([opts[:max_threads], total_chunks].min) do
          Thread.new do
            loop do
              idx = queue.pop(true)
              results[idx] = render_chunk(idx, total_chunks, opts, scene_prompts[idx])
            rescue ThreadError
              break
            end
          end
        end
        workers.each(&:join)
        results
      end

      def render_chunk(idx, _total_chunks, opts, scene_prompt)
        keyframe_url = flux_keyframe(scene_prompt, opts[:lora_id], aspect_ratio: opts[:aspect_ratio])
        clip_url = i2v_clip(keyframe_url, scene_prompt, opts)
        raw_path = File.join(opts[:temp_dir], format("raw_%03d.mp4", idx))
        VideoPost.download_url(clip_url, raw_path)
        VideoPost.apply_analog_filter(raw_path, grain: opts[:grain_intensity], vignette: opts[:vignette])
      end

      def build_scene_prompt(base, idx, total, opts)
        beat = scene_beat(opts[:video_format], idx: idx)
        "#{base} — scene #{idx + 1} of #{total}: #{beat}, cinematic composition, motivated lighting, " \
          "analog 35mm film look, realistic texture, consistent character identity, no text overlays"
      end

      def scene_beat(format, idx:)
        beats = VIDEO_FORMATS.fetch(format)[:beats]
        beats[idx % beats.size]
      end

      def flux_keyframe(scene_prompt, lora_id, aspect_ratio:)
        input = {
          prompt: scene_prompt,
          aspect_ratio: aspect_ratio,
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

      def grade_final(path, opts, retry_label: nil)
        return path unless opts[:final_grade]

        label = retry_label ? "_#{retry_label}" : ""
        graded = path.sub(/\.mp4\z/, "#{label}_#{opts[:grade_preset]}_grade.mp4")
        VideoPost.apply_cinematic_grade(
          path,
          output_path: graded,
          preset: opts[:grade_preset],
          duration: opts[:total_seconds],
          fps: opts[:fps],
          width: opts[:width],
          height: opts[:height]
        )
      end

      def write_manifest(final_path, opts, clips, scene_prompts, regenerated: [])
        path = final_path.sub(/\.mp4\z/, ".json")
        payload = {
          output: final_path,
          backend: opts[:backend],
          format: opts[:video_format],
          grade_preset: opts[:grade_preset],
          seconds: opts[:total_seconds],
          chunk_seconds: opts[:chunk_seconds],
          aspect_ratio: opts[:aspect_ratio],
          fps: opts[:fps],
          lora_id: opts[:lora_id],
          prompt: opts[:prompt],
          clips: clips,
          scene_prompts: scene_prompts,
          regenerated: regenerated,
        }
        File.write(path, JSON.pretty_generate(payload))
        path
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
