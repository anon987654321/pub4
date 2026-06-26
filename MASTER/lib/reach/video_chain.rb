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
        kling: { version: "kwaivgi/kling-v2.1", max_duration: 10 },
        happyhorse: { version: "minimax/video-01-live", max_duration: 12 },
        cogvideox: { version: "thudm/cogvideox-5b-i2v", max_duration: 10 },
        minimax: { version: "minimax/video-01-live", max_duration: 12 },
        comfyui_local: { version: nil, max_duration: 10 },
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
        critique: false,
        agent: nil,
        event_bus: nil,
        replicate: nil,
        root: Master::ROOT
      )
        new(
          root: root,
          agent: agent,
          event_bus: event_bus,
          replicate: replicate || ReplicateClient.new
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
          critique: critique
        )
      end

      def initialize(root:, replicate:, agent: nil, event_bus: nil)
        @root = root
        @replicate = replicate
        @agent = agent
        @bus = event_bus
      end

      def generate(**kwargs)
        opts = normalize_options(kwargs)
        raise Error, "comfyui_local not wired — set COMFYUI_URL and extend VideoChain" if opts[:backend] == :comfyui_local

        FileUtils.mkdir_p([opts[:temp_dir], opts[:output_dir]])
        total_chunks = (opts[:total_minutes] * 60.0 / opts[:chunk_seconds]).ceil
        @bus&.publish(:video_chain_start, backend: opts[:backend], chunks: total_chunks)
        clips = generate_chunks(opts, total_chunks)
        final_path = stitch(clips, opts)
        critique_result = maybe_critique(final_path, opts) if opts[:critique]
        @bus&.publish(:video_chain_done, path: final_path, critique: critique_result)
        { path: final_path, critique: critique_result }
      rescue ArgumentError => e
        raise Error, e.message
      end

      private

      def normalize_options(kwargs)
        backend = kwargs.fetch(:backend, :kling).to_sym
        {
          prompt: kwargs.fetch(:prompt),
          lora_id: kwargs[:lora_id],
          backend: backend,
          config: BACKENDS.fetch(backend) { BACKENDS[:kling] },
          total_minutes: kwargs.fetch(:total_minutes, 2).to_f,
          chunk_seconds: kwargs.fetch(:chunk_seconds, 10).to_i,
          output_dir: expand(kwargs.fetch(:output_dir, "output/cinematic")),
          temp_dir: expand(kwargs.fetch(:temp_dir, "tmp/video_chain")),
          grain_intensity: kwargs.fetch(:grain_intensity, 18).to_i,
          vignette: kwargs.fetch(:vignette, "PI/4").to_s,
          max_threads: [kwargs.fetch(:max_threads, 4).to_i, 1].max,
          motion_intensity: kwargs.fetch(:motion_intensity, 0.75).to_f,
          critique: kwargs.fetch(:critique, false),
        }
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

      def first_output(output)
        url = Array(output).flatten.first
        raise Error, "empty model output" if url.to_s.strip.empty?

        url.to_s
      end

      def stitch(clips, opts)
        stamp = Time.now.strftime("%Y%m%d_%H%M")
        final_path = File.join(
          opts[:output_dir],
          "cinematic_#{opts[:backend]}_#{SecureRandom.hex(6)}_#{stamp}.mp4"
        )
        VideoPost.concat_clips(clips, final_path)
      end

      def maybe_critique(final_path, opts)
        Judge::Council::MotionCritique.critique(
          final_path,
          opts[:prompt],
          agent: @agent,
          event_bus: @bus
        )
      end
    end
  end
end