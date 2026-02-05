# frozen_string_literal: true

module MASTER
  # Swarm generation: create many alternatives, curate to the best
  # Like the orbs: generate 60-70 variations, keep only the worthy ones
  module Swarm
    OUTPUT_DIR = File.join(MASTER::ROOT, 'var', 'swarm')

    # Default generation parameters
    DEFAULTS = {
      count: 64,           # Generate this many variations
      keep: 8,             # Keep only the best
      parallel: 4,         # Concurrent generations
      score_threshold: 0.7 # Minimum quality score to consider
    }.freeze

    # Variation strategies for different content types
    STRATEGIES = {
      image: {
        vary_prompt: true,
        vary_seed: true,
        vary_model: true,
        vary_chain: true,
        vary_guidance: true,
        models: %i[flux_schnell flux_dev sdxl ideogram recraft],
        chains: %i[blockbuster halation neon_noir golden_hour vintage_cinema],
        guidance_range: (5.0..15.0)
      },
      video: {
        vary_prompt: true,
        vary_seed: true,
        vary_model: true,
        vary_duration: false,
        models: %i[hailuo kling luma_ray wan],
        durations: [5, 10]
      },
      audio: {
        vary_prompt: true,
        vary_seed: true,
        vary_model: true,
        models: %i[musicgen riffusion bark],
        durations: [10, 15, 30]
      },
      postpro: {
        vary_preset: true,
        vary_stock: true,
        vary_lens: true,
        vary_intensity: true,
        presets: %i[portrait blockbuster street dream neon_night horror golden_age indie],
        intensity_range: (0.5..1.2)
      }
    }.freeze

    # Quality criteria for ranking
    QUALITY_CRITERIA = {
      aesthetic: {
        weight: 0.3,
        prompt: 'Rate the aesthetic quality of this image from 0 to 10. Consider composition, color harmony, visual appeal.'
      },
      technical: {
        weight: 0.25,
        prompt: 'Rate the technical quality from 0 to 10. Consider sharpness, exposure, noise, artifacts.'
      },
      originality: {
        weight: 0.25,
        prompt: 'Rate the originality from 0 to 10. How unique and creative is this image?'
      },
      emotional: {
        weight: 0.2,
        prompt: 'Rate the emotional impact from 0 to 10. Does this image evoke a strong feeling?'
      }
    }.freeze

    class << self
      # Generate many variations and curate to the best
      def generate(prompt, type: :image, count: nil, keep: nil, strategy: nil)
        FileUtils.mkdir_p(OUTPUT_DIR)

        config = STRATEGIES[type] || STRATEGIES[:image]
        count ||= DEFAULTS[:count]
        keep ||= DEFAULTS[:keep]

        session_id = Time.now.strftime('%Y%m%d_%H%M%S')
        session_dir = File.join(OUTPUT_DIR, session_id)
        FileUtils.mkdir_p(session_dir)

        puts "swarm: generating #{count} #{type} variations"
        puts "       prompt: #{prompt[0..60]}..."
        puts "       session: #{session_id}"

        # Phase 1: Generate all variations
        variations = generate_variations(prompt, type, config, count, session_dir)

        puts "\nswarm: #{variations.size} generated, scoring..."

        # Phase 2: Score each variation
        scored = score_variations(variations, type)

        # Phase 3: Rank and select top candidates
        ranked = scored.sort_by { |v| -v[:score] }
        selected = ranked.first(keep)
        rejected = ranked[keep..]

        # Phase 4: Organize output
        organize_output(session_dir, selected, rejected)

        # Summary
        puts "\nswarm: complete"
        puts "       generated: #{variations.size}"
        puts "       selected: #{selected.size} (score >= #{selected.last&.dig(:score)&.round(2)})"
        puts "       rejected: #{rejected.size}"
        puts "       output: #{session_dir}/selected/"

        Result.ok({
          session: session_id,
          generated: variations.size,
          selected: selected.map { |v| v[:path] },
          scores: selected.map { |v| { path: File.basename(v[:path]), score: v[:score].round(3) } }
        })
      end

      # Generate prompt variations for more diversity
      def vary_prompt(base_prompt, count: 10)
        variations = [base_prompt]

        # Style modifiers
        styles = [
          'cinematic lighting', 'dramatic shadows', 'soft diffused light',
          'golden hour', 'blue hour', 'neon lit', 'candlelit', 'backlit',
          'high contrast', 'low key', 'high key', 'film noir',
          'anamorphic', 'shallow depth of field', 'tilt shift'
        ]

        # Mood modifiers
        moods = [
          'atmospheric', 'moody', 'ethereal', 'gritty', 'dreamy',
          'melancholic', 'euphoric', 'tense', 'serene', 'mysterious'
        ]

        # Technical modifiers
        technical = [
          '35mm film', '65mm IMAX', 'medium format', 'Hasselblad',
          'Kodak Portra', 'Fuji Velvia', 'Cinestill 800T', 'Tri-X pushed',
          'Zeiss lens', 'Cooke Panchro', 'anamorphic Kowa'
        ]

        (count - 1).times do
          mods = []
          mods << styles.sample if rand < 0.7
          mods << moods.sample if rand < 0.5
          mods << technical.sample if rand < 0.4

          varied = "#{base_prompt}, #{mods.join(', ')}"
          variations << varied
        end

        variations.uniq
      end

      # List active swarm sessions
      def list_sessions
        Dir.glob(File.join(OUTPUT_DIR, '*')).select { |d| File.directory?(d) }.map do |dir|
          name = File.basename(dir)
          selected = Dir.glob(File.join(dir, 'selected', '*')).size
          rejected = Dir.glob(File.join(dir, 'rejected', '*')).size
          "  #{name}: #{selected} selected, #{rejected} rejected"
        end.join("\n")
      end

      # Compare two variations side by side
      def compare(path_a, path_b)
        score_a = score_single(path_a)
        score_b = score_single(path_b)

        winner = score_a > score_b ? path_a : path_b
        {
          a: { path: path_a, score: score_a },
          b: { path: path_b, score: score_b },
          winner: winner,
          margin: (score_a - score_b).abs
        }
      end

      private

      def generate_variations(prompt, type, config, count, session_dir)
        variations = []
        prompts = config[:vary_prompt] ? vary_prompt(prompt, count: [count / 4, 5].max) : [prompt]

        count.times do |i|
          seed = config[:vary_seed] ? rand(999_999) : 42
          current_prompt = prompts.sample

          variation = case type
                      when :image
                        generate_image_variation(current_prompt, config, seed, i, session_dir)
                      when :video
                        generate_video_variation(current_prompt, config, seed, i, session_dir)
                      when :audio
                        generate_audio_variation(current_prompt, config, seed, i, session_dir)
                      when :postpro
                        # Requires input image
                        nil
                      end

          if variation && File.exist?(variation.to_s)
            variations << { path: variation, seed: seed, prompt: current_prompt, index: i }
            print '.'
          else
            print 'x'
          end
        end
        puts

        variations
      end

      def generate_image_variation(prompt, config, seed, index, session_dir)
        model = config[:vary_model] ? config[:models].sample : config[:models].first
        chain = config[:vary_chain] ? config[:chains].sample : nil
        guidance = config[:vary_guidance] ? rand(config[:guidance_range]) : 7.5

        if chain
          result = Replicate.run_chain(prompt, chain: chain, seed: seed)
          return nil unless result.ok?
          result.value[:final]
        else
          Replicate.generate_image(prompt, model: model)
        end
      rescue => e
        nil
      end

      def generate_video_variation(prompt, config, seed, index, session_dir)
        # First generate an image, then video
        image = Replicate.generate_image(prompt, model: :flux_schnell)
        return nil unless image && File.exist?(image.to_s)

        model = config[:vary_model] ? config[:models].sample : config[:models].first
        duration = config[:vary_duration] ? config[:durations].sample : 10

        Replicate.generate_video(image, prompt, model: model, duration: duration)
      rescue => e
        nil
      end

      def generate_audio_variation(prompt, config, seed, index, session_dir)
        model = config[:vary_model] ? config[:models].sample : config[:models].first
        duration = config[:durations].sample

        Replicate.generate_audio(prompt, model: model, duration: duration)
      rescue => e
        nil
      end

      def score_variations(variations, type)
        variations.map do |v|
          score = case type
                  when :image then score_image(v[:path])
                  when :video then score_video(v[:path])
                  when :audio then score_audio(v[:path])
                  else 0.5
                  end

          v.merge(score: score)
        end
      end

      def score_image(path)
        return 0.0 unless File.exist?(path.to_s)

        # Use multiple criteria
        scores = {}

        QUALITY_CRITERIA.each do |criterion, config|
          # Quick heuristic scoring (no LLM for speed)
          scores[criterion] = heuristic_score(path, criterion)
        end

        # Weighted average
        total = 0.0
        weight_sum = 0.0

        QUALITY_CRITERIA.each do |criterion, config|
          total += scores[criterion] * config[:weight]
          weight_sum += config[:weight]
        end

        total / weight_sum
      end

      def score_single(path)
        score_image(path)
      end

      def heuristic_score(path, criterion)
        # Fast heuristic scoring based on file analysis
        # In production, this would use LLaVA or CLIP

        begin
          stat = File.stat(path)
          size_kb = stat.size / 1024.0

          case criterion
          when :aesthetic
            # Larger files often have more detail
            [size_kb / 500.0, 1.0].min * 0.6 + rand(0.4)
          when :technical
            # Medium-sized files often best quality
            distance_from_ideal = (size_kb - 300).abs / 300.0
            [1.0 - distance_from_ideal, 0.3].max * 0.7 + rand(0.3)
          when :originality
            # Random for now (would need embedding comparison)
            0.4 + rand(0.6)
          when :emotional
            # Random for now (would need sentiment analysis)
            0.3 + rand(0.7)
          else
            0.5
          end
        rescue StandardError
          0.5
        end
      end

      def score_video(path)
        return 0.0 unless File.exist?(path.to_s)

        # Basic video scoring heuristics
        stat = File.stat(path)
        size_mb = stat.size / (1024.0 * 1024.0)

        # Larger video files generally have more motion/detail
        base_score = [size_mb / 50.0, 1.0].min
        base_score * 0.7 + rand(0.3)
      end

      def score_audio(path)
        return 0.0 unless File.exist?(path.to_s)

        # Basic audio scoring
        stat = File.stat(path)
        0.5 + rand(0.5)
      end

      def organize_output(session_dir, selected, rejected)
        selected_dir = File.join(session_dir, 'selected')
        rejected_dir = File.join(session_dir, 'rejected')

        FileUtils.mkdir_p(selected_dir)
        FileUtils.mkdir_p(rejected_dir)

        selected.each_with_index do |v, i|
          next unless File.exist?(v[:path].to_s)
          ext = File.extname(v[:path])
          new_name = format('best_%02d_score_%0.3f%s', i + 1, v[:score], ext)
          FileUtils.cp(v[:path], File.join(selected_dir, new_name))
        end

        rejected.each_with_index do |v, i|
          next unless File.exist?(v[:path].to_s)
          ext = File.extname(v[:path])
          new_name = format('reject_%02d_score_%0.3f%s', i + 1, v[:score], ext)
          FileUtils.cp(v[:path], File.join(rejected_dir, new_name))
        end

        # Write metadata
        metadata = {
          timestamp: Time.now.iso8601,
          selected: selected.map { |v| { score: v[:score], seed: v[:seed], prompt: v[:prompt] } },
          rejected_count: rejected.size,
          score_range: {
            min: rejected.last&.dig(:score),
            max: selected.first&.dig(:score)
          }
        }

        File.write(File.join(session_dir, 'metadata.json'), JSON.pretty_generate(metadata))
      end
    end
  end
end
