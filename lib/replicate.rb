# frozen_string_literal: true

require 'net/http'
require 'json'
require 'base64'
require 'fileutils'

module MASTER
  module Replicate
    API_URL = 'https://api.replicate.com/v1'
    OUTPUT_DIR = File.join(MASTER::ROOT, 'var', 'replicate')

    # Complete model registry for creative pipelines
    MODELS = {
      # Image generation
      flux_schnell:    'black-forest-labs/flux-schnell',
      flux_dev:        'black-forest-labs/flux-dev',
      flux_pro:        'black-forest-labs/flux-1.1-pro',
      sdxl:            'stability-ai/sdxl',
      sdxl_lightning:  'bytedance/sdxl-lightning-4step',
      ideogram:        'ideogram-ai/ideogram-v2',
      recraft:         'recraft-ai/recraft-v3',

      # Video generation
      hailuo:          'minimax/video-01',
      kling:           'kwaivgi/kling-v2.5-turbo-pro',
      luma_ray:        'luma/ray-2',
      wan:             'wan-video/wan-2.5-i2v',
      sora:            'openai/sora-2',
      stable_video:    'stability-ai/stable-video-diffusion',

      # Enhancement and upscaling
      real_esrgan:     'nightmareai/real-esrgan',
      gfpgan:          'tencentarc/gfpgan',
      codeformer:      'sczhou/codeformer',
      clarity:         'lucataco/clarity-upscaler',
      supir:           'zsxkib/supir',
      aura_sr:         'fofr/aura-sr',

      # Style and effects
      depth_anything:  'adirik/depth-anything-v2',
      controlnet:      'jagilley/controlnet-canny',
      remove_bg:       'lucataco/remove-bg',
      face_to_many:    'fofr/face-to-many',
      instruct_pix:    'timothybrooks/instruct-pix2pix',
      style_transfer:  'jagilley/neural-style-transfer',

      # Color grading
      bigcolor:        'cjwbw/bigcolor',
      ddcolor:         'piddnad/ddcolor',
      deoldify:        'arielreplicate/deoldify',

      # Vision and analysis
      llava:           'yorickvp/llava-13b',
      blip:            'salesforce/blip',
      clip:            'pharmapsychotic/clip-interrogator',

      # Audio
      musicgen:        'meta/musicgen',
      bark:            'suno-ai/bark',
      whisper:         'openai/whisper',
      riffusion:       'riffusion/riffusion',

      # Text-to-speech (fast to slow)
      minimax_turbo:   'minimax/speech-02-turbo',
      minimax_hd:      'minimax/speech-02-hd',
      kokoro:          'jaaari/kokoro-82m',

      # 3D and depth
      depth_pro:       'apple/depth-pro',
      marigold:        'prs-eth/marigold',
      zoedepth:        'isl-org/zoedepth'
    }.freeze

    # Cinematography chains: each step builds on the previous
    CHAINS = {
      # Classic film looks
      vintage_cinema: {
        description: 'Aged film stock with authentic grain and color fade',
        steps: [
          { model: :flux_dev, action: :generate },
          { model: :deoldify, action: :colorize, params: { artistic: true } },
          { model: :instruct_pix, action: :edit, prompt: 'add subtle film grain, slight color fade, warm shadows' },
          { model: :real_esrgan, action: :upscale }
        ]
      },

      # Blockbuster orange and teal
      blockbuster: {
        description: 'Modern Hollywood color science with teal shadows and orange highlights',
        steps: [
          { model: :flux_pro, action: :generate },
          { model: :instruct_pix, action: :edit, prompt: 'dramatic orange and teal color grading, strong contrast, cinematic lens flare' },
          { model: :clarity, action: :upscale }
        ]
      },

      # Blade Runner neon noir
      neon_noir: {
        description: 'Cyberpunk aesthetics with neon reflections and rain-slicked streets',
        steps: [
          { model: :flux_dev, action: :generate },
          { model: :depth_anything, action: :depth },
          { model: :instruct_pix, action: :edit, prompt: 'neon lights reflecting on wet pavement, cyberpunk atmosphere, purple and cyan, high contrast shadows' },
          { model: :real_esrgan, action: :upscale }
        ]
      },

      # Our signature halation
      halation: {
        description: 'Warm glow around highlights like 35mm film with light leaks',
        steps: [
          { model: :flux_schnell, action: :generate },
          { model: :instruct_pix, action: :edit, prompt: 'warm orange-red halation around bright areas, 35mm film grain, soft ethereal glow, no harsh edges, gentle light leaks' },
          { model: :gfpgan, action: :enhance }
        ]
      },

      # Wes Anderson symmetry
      anderson: {
        description: 'Perfect symmetry with pastel palette and whimsical framing',
        steps: [
          { model: :flux_dev, action: :generate },
          { model: :instruct_pix, action: :edit, prompt: 'perfectly centered symmetric composition, pastel color palette, whimsical staging, flat perspective' },
          { model: :clarity, action: :upscale }
        ]
      },

      # Horror desaturation
      horror: {
        description: 'Unsettling atmosphere with crushed blacks and sickly greens',
        steps: [
          { model: :flux_schnell, action: :generate },
          { model: :instruct_pix, action: :edit, prompt: 'extreme desaturation, sickly greenish tint, deep crushed shadows, film grain, uncomfortable atmosphere' },
          { model: :real_esrgan, action: :upscale }
        ]
      },

      # Golden hour magic
      golden_hour: {
        description: 'Warm sunset light with long shadows and amber atmosphere',
        steps: [
          { model: :flux_dev, action: :generate },
          { model: :instruct_pix, action: :edit, prompt: 'golden hour sunlight, long dramatic shadows, warm amber tones, soft lens flares, magic hour' },
          { model: :gfpgan, action: :enhance }
        ]
      },

      # Day for night
      day_for_night: {
        description: 'Classic technique to simulate moonlight from daylight footage',
        steps: [
          { model: :flux_schnell, action: :generate },
          { model: :instruct_pix, action: :edit, prompt: 'day for night, deep blue filter, artificial moonlight, visible stars, underexposed shadows' },
          { model: :real_esrgan, action: :upscale }
        ]
      },

      # Bleach bypass
      bleach_bypass: {
        description: 'Skipped bleach process for desaturated high-contrast look',
        steps: [
          { model: :flux_dev, action: :generate },
          { model: :instruct_pix, action: :edit, prompt: 'bleach bypass effect, reduced saturation, increased contrast, silvery highlights, gritty texture' },
          { model: :clarity, action: :upscale }
        ]
      },

      # Technicolor three-strip
      technicolor: {
        description: 'Vivid saturated primaries like classic Hollywood musicals',
        steps: [
          { model: :flux_pro, action: :generate },
          { model: :ddcolor, action: :colorize },
          { model: :instruct_pix, action: :edit, prompt: 'technicolor three-strip, vivid saturated reds blues and greens, classic Hollywood glamour' },
          { model: :supir, action: :upscale }
        ]
      },

      # Infrared false color
      infrared: {
        description: 'Infrared photography with white foliage and surreal colors',
        steps: [
          { model: :flux_dev, action: :generate },
          { model: :instruct_pix, action: :edit, prompt: 'infrared photography effect, white vegetation, pink sky, false color, surreal dreamlike' },
          { model: :real_esrgan, action: :upscale }
        ]
      },

      # Full pipeline with video
      cinematic_video: {
        description: 'Complete image-to-video pipeline with color grading',
        steps: [
          { model: :flux_pro, action: :generate },
          { model: :depth_anything, action: :depth },
          { model: :instruct_pix, action: :edit, prompt: 'cinematic color grading, anamorphic lens flare, shallow depth of field' },
          { model: :hailuo, action: :video, duration: 10 },
          { model: :musicgen, action: :audio, prompt: 'cinematic orchestral score, dramatic' }
        ]
      },

      # Experimental glitch
      glitch: {
        description: 'Digital artifacts and datamosh effects',
        steps: [
          { model: :flux_schnell, action: :generate },
          { model: :instruct_pix, action: :edit, prompt: 'digital glitch artifacts, chromatic aberration, scan lines, datamosh corruption, VHS tracking' },
          { model: :style_transfer, action: :stylize }
        ]
      },

      # Maximum chaos: randomized
      chaos: {
        description: 'Randomly assembled pipeline for unexpected results',
        steps: :random
      }
    }.freeze

    # Color grading presets for instruct-pix2pix
    GRADES = [
      'teal and orange blockbuster, high contrast, crushed blacks',
      'film noir black and white, deep shadows, single light source',
      'vibrant pop art saturation, bold primaries, flat shadows',
      'muted earth tones, desaturated greens and browns, natural',
      'neon cyberpunk, purple and cyan, wet reflections, high contrast',
      'soft pastel colors, diffused light, dreamy ethereal',
      'harsh industrial cold blue steel, clinical lighting',
      'warm sepia vintage photograph, aged paper texture',
      'cross-processed film, shifted magentas and cyans',
      'bleach bypass, low saturation, metallic highlights',
      'technicolor vivid primaries, golden age Hollywood',
      'day for night blue filter, artificial moonlight',
      'infrared false color, white vegetation, pink sky',
      'film halation, red glow around highlights, soft edges',
      'anamorphic oval bokeh, horizontal lens flare, wide aspect'
    ].freeze

    class << self
      # ─────────────────────────────────────────────────────────────────────
      # Public API
      # ─────────────────────────────────────────────────────────────────────

      def generate_image(prompt, model: :flux_schnell)
        model_id = MODELS[model] || MODELS[:flux_schnell]
        run_model(model_id, { prompt: prompt, aspect_ratio: '16:9' })
      end

      def generate_video(image_url, prompt, model: :hailuo, duration: 10)
        model_id = MODELS[model] || MODELS[:hailuo]

        input = case model
                when :sora
                  { prompt: prompt, first_frame_image: image_url, duration: duration }
                when :kling
                  { image: image_url, prompt: prompt, duration: duration, aspect_ratio: '16:9' }
                when :luma_ray
                  { prompt: prompt, start_image: image_url, aspect_ratio: '16:9' }
                when :wan
                  { image: image_url, prompt: prompt, duration: duration }
                else
                  { prompt: prompt, first_frame_image: image_url, prompt_optimizer: true }
                end

        run_model(model_id, input)
      end

      def generate_audio(prompt, model: :musicgen, duration: 10)
        model_id = MODELS[model] || MODELS[:musicgen]
        run_model(model_id, { prompt: prompt, duration: duration })
      end

      def speak(text, voice: 'Casual_Guy', speed: 1.0, turbo: true)
        if turbo
          speak_turbo(text, voice: voice)
        else
          # Kokoro uses af_/am_/bf_/bm_ prefixes
          kokoro_voice = voice.start_with?('male') ? 'am_adam' : 'af_bella'
          run_model(MODELS[:kokoro], { text: text, voice: kokoro_voice, speed: speed })
        end
      end

      def speak_turbo(text, voice: 'Casual_Guy')
        run_model_by_name('minimax/speech-02-turbo', { text: text, voice_id: voice })
      end

      # All-in-one: generate chunks and play them with pipelining
      def say(text, voice: 'Casual_Guy', chunk_words: 10)
        files = speak_stream(text, voice: voice, chunk_words: chunk_words)
        play_files(files)
        files.size
      end

      # Pipelined: generate and play concurrently (starts playing ASAP)
      def say_fast(text, voice: 'Casual_Guy', chunk_words: 10)
        require 'fileutils'
        FileUtils.mkdir_p(OUTPUT_DIR)

        chunks = smart_chunk(text, chunk_words)
        queue = Thread::Queue.new
        done = false

        # Producer: generate audio chunks
        producer = Thread.new do
          chunks.each_with_index do |chunk, i|
            result = speak_turbo(chunk.strip, voice: voice)
            queue << result if result && File.exist?(result.to_s)
          end
          done = true
        end

        # Consumer: play as they arrive (1 sec max gap)
        played = 0
        loop do
          if queue.empty?
            break if done
            sleep 0.5
            next
          end

          file = queue.pop
          play_single(file)
          played += 1
        end

        producer.join
        played
      end

      def play_single(file)
        case RUBY_PLATFORM
        when /mingw|mswin|cygwin/
          system("powershell", "-Command", "
            Add-Type -AssemblyName PresentationCore
            $p = New-Object System.Windows.Media.MediaPlayer
            $p.Open([Uri]'#{file.gsub('/', '\\')}')
            Start-Sleep -Milliseconds 200
            $d = $p.NaturalDuration.TimeSpan.TotalMilliseconds
            if ($d -lt 500) { $d = 3000 }
            $p.Play()
            Start-Sleep -Milliseconds ($d + 100)
          ")
        when /darwin/
          system("afplay", file)
        else
          system("mpv", "--no-video", "--really-quiet", file) rescue system("ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", file)
        end
      end

      # Play audio files sequentially (cross-platform)
      def play_files(files)
        case RUBY_PLATFORM
        when /mingw|mswin|cygwin/
          play_windows(files)
        when /darwin/
          play_macos(files)
        when /linux|openbsd|freebsd/
          play_unix(files)
        else
          puts "Unsupported platform for audio playback"
        end
      end

      def play_windows(files)
        # Use PowerShell MediaPlayer with proper duration detection
        script = <<~PS
          Add-Type -AssemblyName PresentationCore
          $p = New-Object System.Windows.Media.MediaPlayer
          $files = @(#{files.map { |f| "'#{f.gsub('/', '\\')}'" }.join(', ')})
          foreach ($f in $files) {
            $p.Open([Uri]$f)
            Start-Sleep -Milliseconds 300
            $duration = $p.NaturalDuration.TimeSpan.TotalMilliseconds
            if ($duration -lt 500) { $duration = 3000 }
            $p.Play()
            Start-Sleep -Milliseconds ($duration + 200)
          }
        PS
        system("powershell", "-Command", script)
      end

      def play_macos(files)
        files.each { |f| system("afplay", f) }
      end

      def play_unix(files)
        # Try mpv, ffplay, or aplay
        player = %w[mpv ffplay aplay paplay].find { |p| system("which #{p} > /dev/null 2>&1") }
        return puts "No audio player found (install mpv or ffmpeg)" unless player

        case player
        when 'mpv'
          files.each { |f| system("mpv", "--no-video", "--really-quiet", f) }
        when 'ffplay'
          files.each { |f| system("ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", f) }
        else
          files.each { |f| system(player, f) }
        end
      end

      # Streaming TTS: split into chunks, generate sequentially
      def speak_stream(text, voice: 'Casual_Guy', chunk_words: 8)
        require 'fileutils'
        FileUtils.mkdir_p(OUTPUT_DIR)

        # Split into sentence fragments at natural boundaries
        chunks = smart_chunk(text, chunk_words)
        audio_files = []

        chunks.each_with_index do |chunk, i|
          print "  [#{i + 1}/#{chunks.size}] "
          result = speak_turbo(chunk.strip, voice: voice)
          if result && File.exist?(result.to_s)
            audio_files << result
            puts "✓"
          else
            puts "✗"
          end
        end

        audio_files
      end

      def smart_chunk(text, target_words)
        # Split at natural pause points: periods, commas, semicolons, conjunctions
        # But keep chunks roughly target_words size
        words = text.split
        chunks = []
        current = []

        words.each do |word|
          current << word
          # Check for natural break points
          if current.size >= target_words || 
             word.match?(/[.!?;]$/) || 
             (current.size >= target_words / 2 && word.match?(/[,:]$/))
            chunks << current.join(' ')
            current = []
          end
        end

        chunks << current.join(' ') unless current.empty?
        chunks.reject(&:empty?)
      end

      def run_model_by_name(model_name, input)
        api_key = ENV['REPLICATE_API_TOKEN']
        return 'REPLICATE_API_TOKEN not set' unless api_key

        uri = URI("#{API_URL}/models/#{model_name}/predictions")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)
        request['Authorization'] = "Token #{api_key}"
        request['Content-Type'] = 'application/json'
        request.body = { input: input }.to_json

        response = http.request(request)
        result = JSON.parse(response.body)

        return result['error'] if result['error']

        poll_prediction(result['id'], api_key)
      end

      def describe_image(path)
        return 'File not found' unless File.exist?(path)

        uri = file_to_data_uri(path)
        run_model(MODELS[:llava], { image: uri, prompt: 'Describe this image in detail.' })
      end

      def transcribe(path)
        return 'File not found' unless File.exist?(path)

        data = Base64.strict_encode64(File.binread(path))
        run_model(MODELS[:whisper], { audio: "data:audio/mp3;base64,#{data}" })
      end

      def upscale(path, model: :real_esrgan, scale: 4)
        return 'File not found' unless File.exist?(path)

        uri = file_to_data_uri(path)
        model_id = MODELS[model] || MODELS[:real_esrgan]
        run_model(model_id, { image: uri, scale: scale })
      end

      def edit_image(path, prompt, model: :instruct_pix)
        return 'File not found' unless File.exist?(path)

        uri = file_to_data_uri(path)
        model_id = MODELS[model] || MODELS[:instruct_pix]
        run_model(model_id, { image: uri, prompt: prompt, image_guidance_scale: 1.5 })
      end

      def depth_map(path)
        return 'File not found' unless File.exist?(path)

        uri = file_to_data_uri(path)
        run_model(MODELS[:depth_anything], { image: uri })
      end

      def remove_background(path)
        return 'File not found' unless File.exist?(path)

        uri = file_to_data_uri(path)
        run_model(MODELS[:remove_bg], { image: uri })
      end

      def colorize(path, model: :ddcolor)
        return 'File not found' unless File.exist?(path)

        uri = file_to_data_uri(path)
        model_id = MODELS[model] || MODELS[:ddcolor]
        run_model(model_id, { image: uri })
      end

      # ─────────────────────────────────────────────────────────────────────
      # Chain execution
      # ─────────────────────────────────────────────────────────────────────

      def run_chain(prompt, chain: :blockbuster, seed: nil)
        FileUtils.mkdir_p(OUTPUT_DIR)
        seed ||= rand(999_999)

        chain_config = CHAINS[chain.to_sym]
        return Result.err("Unknown chain: #{chain}") unless chain_config

        steps = chain_config[:steps] == :random ? random_pipeline : chain_config[:steps]

        puts "  chain: #{chain} (#{steps.size} steps, seed #{seed})"
        context = { prompt: prompt, seed: seed, artifacts: [] }

        steps.each_with_index do |step, idx|
          model_name = step[:model]
          action = step[:action]
          puts "  [#{idx + 1}/#{steps.size}] #{model_name} (#{action})"

          result = execute_step(step, context)

          if result && !result.include?('error') && !result.include?('Failed')
            context[:current] = result
            context[:artifacts] << { step: idx + 1, model: model_name, action: action, output: result }
          else
            puts "    warning: step failed, continuing with previous result"
          end
        end

        Result.ok({
          chain: chain,
          seed: seed,
          steps: context[:artifacts],
          final: context[:artifacts].last&.dig(:output)
        })
      end

      def wild_chain(prompt, steps: 5, seed: nil)
        seed ||= rand(999_999)
        srand(seed)

        puts "  wild chain: #{steps} steps, seed #{seed}"
        pipeline = random_pipeline(steps)

        context = { prompt: prompt, seed: seed, artifacts: [] }

        pipeline.each_with_index do |step, idx|
          puts "  [#{idx + 1}/#{steps}] #{step[:model]} (#{step[:action]})"

          result = execute_step(step, context)

          if result && !result.include?('error')
            context[:current] = result
            context[:artifacts] << { step: idx + 1, model: step[:model], output: result }
          end
        end

        Result.ok({
          chain: :wild,
          seed: seed,
          pipeline: pipeline.map { |s| "#{s[:model]}:#{s[:action]}" },
          artifacts: context[:artifacts],
          final: context[:artifacts].last&.dig(:output)
        })
      end

      def list_chains
        CHAINS.map { |name, config|
          steps = config[:steps] == :random ? 'random' : "#{config[:steps].size} steps"
          "  #{name}: #{config[:description]} (#{steps})"
        }.join("\n")
      end

      def list_models
        MODELS.map { |key, id| "  #{key}: #{id}" }.join("\n")
      end

      def random_grade
        GRADES.sample
      end

      # ─────────────────────────────────────────────────────────────────────
      # Private implementation
      # ─────────────────────────────────────────────────────────────────────

      private

      def random_pipeline(length = nil)
        length ||= rand(3..6)
        pipeline = []

        # First: always generate
        generators = [:flux_schnell, :flux_dev, :flux_pro, :sdxl, :ideogram]
        pipeline << { model: generators.sample, action: :generate }

        # Middle: effects and enhancements
        effects = [:instruct_pix, :style_transfer, :ddcolor, :deoldify]
        enhancers = [:real_esrgan, :gfpgan, :clarity, :supir, :codeformer]

        (length - 2).times do
          if rand < 0.6
            pipeline << { model: effects.sample, action: :edit, prompt: random_grade }
          else
            pipeline << { model: enhancers.sample, action: :enhance }
          end
        end

        # Last: upscale or video
        if rand < 0.3
          videos = [:hailuo, :kling, :luma_ray, :wan]
          pipeline << { model: videos.sample, action: :video, duration: 10 }
        else
          pipeline << { model: enhancers.sample, action: :upscale }
        end

        pipeline
      end

      def execute_step(step, context)
        model_id = MODELS[step[:model]]
        return "Unknown model: #{step[:model]}" unless model_id

        case step[:action]
        when :generate
          input = { prompt: context[:prompt], aspect_ratio: '16:9' }
          input[:seed] = context[:seed] if context[:seed]
          run_model(model_id, input)

        when :edit
          return 'No image to edit' unless context[:current]
          prompt = step[:prompt] || random_grade
          run_model(model_id, { image: ensure_uri(context[:current]), prompt: prompt })

        when :upscale, :enhance
          return 'No image to enhance' unless context[:current]
          run_model(model_id, { image: ensure_uri(context[:current]) })

        when :depth
          return 'No image for depth' unless context[:current]
          run_model(model_id, { image: ensure_uri(context[:current]) })

        when :colorize
          return 'No image to colorize' unless context[:current]
          run_model(model_id, { image: ensure_uri(context[:current]) })

        when :stylize
          return 'No image to stylize' unless context[:current]
          run_model(model_id, { content_image: ensure_uri(context[:current]) })

        when :video
          return 'No image for video' unless context[:current]
          duration = step[:duration] || 10
          generate_video(ensure_uri(context[:current]), context[:prompt], model: step[:model], duration: duration)

        when :audio
          prompt = step[:prompt] || 'cinematic orchestral score'
          generate_audio(prompt, model: step[:model])

        else
          "Unknown action: #{step[:action]}"
        end
      end

      def run_model(model, input)
        api_key = ENV['REPLICATE_API_TOKEN']
        return 'REPLICATE_API_TOKEN not set' unless api_key

        # Use /models/ endpoint for official models
        uri = if model.include?('/')
                URI("#{API_URL}/models/#{model}/predictions")
              else
                URI("#{API_URL}/predictions")
              end

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 300

        request = Net::HTTP::Post.new(uri)
        request['Authorization'] = "Token #{api_key}"
        request['Content-Type'] = 'application/json'
        request.body = { input: input }.to_json

        response = http.request(request)
        data = JSON.parse(response.body)

        return "API error: #{data['error']}" if data['error']

        poll_prediction(data['id'], api_key)
      end

      def poll_prediction(id, api_key, timeout: 300)
        uri = URI("#{API_URL}/predictions/#{id}")
        start = Time.now

        loop do
          return 'Timeout waiting for prediction' if Time.now - start > timeout

          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true

          request = Net::HTTP::Get.new(uri)
          request['Authorization'] = "Token #{api_key}"

          response = http.request(request)
          data = JSON.parse(response.body)

          case data['status']
          when 'succeeded'
            output = data['output']
            return save_output(output)
          when 'failed', 'canceled'
            return "Failed: #{data['error'] || 'unknown error'}"
          end

          print '.'
          sleep 3
        end
      end

      def save_output(output)
        FileUtils.mkdir_p(OUTPUT_DIR)

        case output
        when String
          if output.start_with?('http')
            ext = File.extname(URI.parse(output).path)
            ext = '.webp' if ext.empty?
            filename = "#{Time.now.to_i}_#{rand(1000)}#{ext}"
            path = File.join(OUTPUT_DIR, filename)
            download(output, path)
            path
          else
            output
          end
        when Array
          output.map { |o| save_output(o) }.first
        else
          output.to_s
        end
      end

      def download(url, path)
        uri = URI(url)
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
          response = http.get(uri.request_uri)
          File.binwrite(path, response.body)
        end
        path
      end

      def file_to_data_uri(path)
        data = Base64.strict_encode64(File.binread(path))
        ext = File.extname(path).sub('.', '')
        ext = 'jpeg' if ext == 'jpg'
        "data:image/#{ext};base64,#{data}"
      end

      def ensure_uri(input)
        return input if input.start_with?('http', 'data:')
        return file_to_data_uri(input) if File.exist?(input)
        input
      end
    end
  end
end
