#!/usr/bin/env ruby
# frozen_string_literal: true

# Repligen - Complete AI Media Generation Pipeline

# v13.0 - Consolidated with model indexing, chain generation, and LLM guidance

require "net/http"

require "json"

require "fileutils"

require "base64"

VERSION = "13.0.0"

TOKEN = ENV["REPLICATE_API_TOKEN"] || raise("Set REPLICATE_API_TOKEN")

class Repligen

  COMMANDS = {

    "generate" => "Generate single image from natural language prompt",

    "video" => "Generate image + video (10s with best available model)",

    "catwalk" => "Generate runway/catwalk video with fashion presets",

    "lora" => "Train custom LoRA from photos in __lora/{subject}/",

    "enhance" => "Enhance training photos (remove bg, sharpen, upscale)",

    "commercial" => "Generate multi-clip commercial with cinematography",

    "chain" => "Execute model chain (ra2 → video)",

    "index" => "Index Replicate models to local database",

    "search" => "Search indexed models",

    "wild" => "Wild chain: random multi-model pipeline for unique outputs",

    "help" => "Show this help"

  }

  # Wild Chain Mode: Random model combinations for experimental outputs
  WILD_CHAIN = {
    image_gen: [
      { model: "black-forest-labs/flux-pro", name: "Flux Pro" },
      { model: "black-forest-labs/flux-dev", name: "Flux Dev" },
      { model: "stability-ai/sdxl", name: "SDXL" },
      { model: "ideogram-ai/ideogram-v2", name: "Ideogram V2" },
      { model: "recraft-ai/recraft-v3", name: "Recraft V3" }
    ],
    video_gen: [
      { model: "minimax/video-01", name: "Hailuo 2.3" },
      { model: "kwaivgi/kling-v2.5-turbo-pro", name: "Kling 2.5" },
      { model: "luma/ray-2", name: "Luma Ray 2" },
      { model: "wan-video/wan-2.5-i2v", name: "WAN 2.5" },
      { model: "openai/sora-2", name: "Sora 2" }
    ],
    enhance: [
      { model: "nightmareai/real-esrgan", name: "Real-ESRGAN 4x" },
      { model: "tencentarc/gfpgan", name: "GFPGAN Face" },
      { model: "sczhou/codeformer", name: "CodeFormer" },
      { model: "lucataco/clarity-upscaler", name: "Clarity 4x" }
    ],
    style: [
      { model: "adirik/depth-anything-v2", name: "Depth Map" },
      { model: "jagilley/controlnet-canny", name: "Canny Edge" },
      { model: "lucataco/remove-bg", name: "Remove BG" },
      { model: "fofr/face-to-many", name: "Face Style" }
    ],
    colorgrade: [
      { model: "cjwbw/bigcolor", name: "BigColor" },
      { model: "piddnad/ddcolor", name: "DDColor" }
    ],
    audio: [
      { model: "meta/musicgen", name: "MusicGen" },
      { model: "suno-ai/bark", name: "Bark TTS" },
      { model: "openai/whisper", name: "Whisper STT" }
    ]
  }

  CATWALK_STYLES = {
    "haute_couture" => "haute couture evening gown, elegant luxury fashion",
    "designer_suit" => "designer business suit, professional power look",
    "avant_garde" => "avant-garde fashion, bold experimental design",
    "streetwear" => "luxury streetwear, high-end casual style",
    "red_carpet" => "red carpet glamour, celebrity fashion"
  }

  CATWALK_LIGHTING = {
    "runway" => "dramatic runway spotlight with soft bokeh background",
    "golden" => "golden hour natural light, warm tones",
    "studio" => "professional studio fashion lighting",
    "cinematic" => "cinematic blue hour lighting with rim light"
  }

  def initialize

    @token = TOKEN

    @out = File.join(File.dirname(__FILE__), "repligen")

    @db_path = File.join(File.dirname(__FILE__), "repligen_models.db")

    FileUtils.mkdir_p(@out)

  end

  def api(method, path, body = nil)

    uri = URI("https://api.replicate.com/v1#{path}")

    req = build_request(method, uri, body)

    execute_request(uri, req)

  rescue => e

    puts "❌ API error: #{e.message}"

    nil

  end

  def build_request(method, uri, body)

    req = method == :get ? Net::HTTP::Get.new(uri) : Net::HTTP::Post.new(uri)

    req["Authorization"] = "Token #{@token}"

    req["Content-Type"] = "application/json"

    req.body = body.to_json if body

    req

  end

  def execute_request(uri, req)

    Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }

  end

  def wait_for_completion(id, name)

    print "⏳ #{name}..."

    loop do

      sleep 3

      res = api(:get, "/predictions/#{id}")

      return handle_api_failure(name) unless res

      data = JSON.parse(res.body)

      case data["status"]

      when "succeeded"

        puts " ✓"

        return data["output"].is_a?(Array) ? data["output"][0] : data["output"]

      when "failed"

        puts " ✗ #{data["error"]}"

        return nil

      else

        print "."

      end

    end

  rescue => e

    puts " ✗ #{e.message}"

    nil

  end

  def handle_api_failure(name)

    puts " ✗ API request failed for #{name}"

    nil

  end

  def download(url, filename)

    puts "📥 Downloading..."

    File.write(filename, Net::HTTP.get(URI(url)))

    puts "✓ Saved: #{filename}"

  rescue => e

    puts "❌ Download failed: #{e.message}"

    false

  end

  def generate_image(prompt, lora: nil)

    puts "🎨 Generating image..."

    puts "Prompt: #{prompt[0..100]}..."

    res = lora ? generate_with_lora(prompt) : generate_with_flux_pro(prompt)

    return nil unless res

    wait_for_completion(JSON.parse(res.body)["id"], lora ? "RA2 LoRA" : "Flux Pro")

  end

  def generate_with_lora(prompt)

    api(:post, "/predictions", {

      version: "387d19ad57699a915fbb12f89e61ffae24a2b04a3d5f065b59281e929d533ae5",

      input: {

        prompt: prompt,

        aspect_ratio: "16:9",

        output_format: "webp",

        num_inference_steps: 35

      }

    })

  end

  def generate_with_flux_pro(prompt)

    api(:post, "/models/black-forest-labs/flux-pro/predictions", {

      input: {

        prompt: prompt,

        aspect_ratio: "16:9",

        output_format: "webp"

      }

    })

  end

  def extend_video(video_url, prompt, extension_prompt = nil)

    puts "

📹 Extending video with Luma Ray 2..."

    # Luma Ray 2 Extend feature - adds 5-10s per extension

    res = api(:post, "/models/luma/ray-2/predictions", {

      input: {

        prompt: extension_prompt || prompt,

        extend_video: video_url,

        aspect_ratio: "16:9"

      }

    })

    wait_for_completion(JSON.parse(res.body)["id"], "Luma Extend")

  end

  def generate_video(image_url, prompt, duration: 10, model: :hailuo)

    puts "

🎬 Generating #{duration}s video..."

    case model

    when :sora

      # OpenAI Sora 2 - best quality with native audio (131K+ runs)

      res = api(:post, "/models/openai/sora-2/predictions", {

        input: {

          prompt: prompt,

          first_frame_image: image_url,

          duration: duration

        }

      })

      wait_for_completion(JSON.parse(res.body)["id"], "Sora 2 #{duration}s")

    when :kling

      # Kling 2.5 Turbo Pro - 1.4M runs, realistic physics (fastest)

      res = api(:post, "/models/kwaivgi/kling-v2.5-turbo-pro/predictions", {

        input: {

          image: image_url,

          prompt: prompt,

          duration: duration,

          aspect_ratio: "16:9"

        }

      })

      wait_for_completion(JSON.parse(res.body)["id"], "Kling 2.5 Pro #{duration}s")

    when :wan

      # Wan 2.5 - open source, audio sync, 109K runs (affordable)

      res = api(:post, "/models/wan-video/wan-2.5-i2v/predictions", {

        input: {

          image: image_url,

          prompt: prompt,

          duration: duration

        }

      })

      wait_for_completion(JSON.parse(res.body)["id"], "Wan 2.5 #{duration}s")

    else

      # Minimax Hailuo 2.3 - default, good motion (affordable)

      res = api(:post, "/models/minimax/video-01/predictions", {

        input: {

          prompt: prompt,

          first_frame_image: image_url,

          prompt_optimizer: true

        }

      })

      wait_for_completion(JSON.parse(res.body)["id"], "Hailuo 2.3 10s")

    end

  end

  def enhance_for_video(image_url, name)

    puts "

  🔧 Enhancing image for better video quality..."

    # 1. Generate depth map for better 3D motion

    puts "  [1/3] Depth map generation..."

    res = api(:post, "/models/adirik/depth-anything-v2/predictions", {

      input: { image: image_url }

    })

    depth = wait_for_completion(JSON.parse(res.body)["id"], "Depth")

    # 2. Edge refinement with canny

    puts "  [2/3] Edge refinement..."

    res = api(:post, "/models/jagilley/controlnet-canny/predictions", {

      input: {

        image: image_url,

        prompt: "high quality, sharp edges, professional photography",

        num_inference_steps: 20

      }

    })

    refined = wait_for_completion(JSON.parse(res.body)["id"], "Edge Refine")

    # 3. Optional relighting for consistency

    puts "  [3/3] Lighting enhancement..."

    res = api(:post, "/models/jagilley/controlnet-brightness/predictions", {

      input: {

        image: refined || image_url,

        prompt: "cinematic lighting, golden hour, natural illumination",

        brightness: 0.7,

        num_inference_steps: 20

      }

    })

    enhanced = wait_for_completion(JSON.parse(res.body)["id"], "Relight")

    enhanced || refined || image_url

  end

  def enhance_training_photos(subject)

    input_dir = File.join("__lora", subject)

    output_dir = File.join("__lora", "#{subject}_enhanced")

    unless Dir.exist?(input_dir)

      puts "❌ Directory not found: #{input_dir}"

      return

    end

    FileUtils.mkdir_p(output_dir)

    images = Dir[File.join(input_dir, "*.{jpg,jpeg,png}")].sort

    puts "

🎨 ENHANCING TRAINING PHOTOS"

    puts "="*70

    puts "Subject: #{subject}"

    puts "Input: #{images.length} photos"

    puts "Strategy: BiRefNet background removal + upscale + face enhance"

    puts "="*70

    images.each_with_index do |img_path, i|

      name = File.basename(img_path, ".*")

      puts "

[#{i+1}/#{images.length}] #{name}"

      # Read and encode

      img_data = File.read(img_path)

      img_url = "data:image/jpeg;base64,#{Base64.strict_encode64(img_data)}"

      # Enhance

      enhanced = enhance_image(img_url, name)

      next unless enhanced

      # Download

      output_path = File.join(output_dir, "#{name}.png")

      download(enhanced, output_path)

      sleep 1

    end

    final_count = Dir[File.join(output_dir, "*")].length

    puts "

" + "="*70

    puts "✨ ENHANCEMENT COMPLETE!"

    puts "="*70

    puts "Enhanced: #{final_count} photos"

    puts "Output: #{output_dir}/"

    puts "

Next: Train LoRA with enhanced photos"

    puts "  cd __lora && zip -r #{subject}_enhanced_training.zip #{subject}_enhanced/*.png"

  end

  def train_lora(subject)

    input_dir = File.join("__lora", subject)

    unless Dir.exist?(input_dir)

      puts "❌ Directory not found: #{input_dir}"

      puts "Create it and add 10-20 training photos"

      return

    end

    images = Dir[File.join(input_dir, "*.{jpg,jpeg,png}")].sort

    if images.length < 10

      puts "❌ Need at least 10 images, found #{images.length}"

      return

    end

    puts "

🎓 LoRA TRAINING: #{subject}"

    puts "="*70

    puts "Images: #{images.length}"

    puts "Trigger word: #{subject.upcase}"

    puts "

To train on Replicate:"

    puts "1. Create zip: cd __lora && zip -r #{subject}_training.zip #{subject}/*.jpg"

    puts "2. Go to: https://replicate.com/ostris/flux-dev-lora-trainer/train"

    puts "3. Upload zip and set trigger word: #{subject.upcase}"

    puts "4. Training takes 15-30 minutes (~$10)"

    puts "

After training, use with:"

    puts "  ruby repligen.rb generate '#{subject.upcase} woman as athlete, cinematic portrait'"

  end

  def generate_catwalk(subject, style: "haute_couture", lighting: "runway", audio_path: nil)
    style_desc = CATWALK_STYLES[style] || style
    light_desc = CATWALK_LIGHTING[lighting] || lighting

    prompt = "#{subject} walking confidently down fashion runway, #{style_desc}, " \
             "professional supermodel pose, full body shot, #{light_desc}, " \
             "elegant powerful stride, high-end fashion photography, vogue magazine quality, " \
             "sharp focus on model, bokeh background, cinematic composition, 16:9 aspect ratio"

    puts "
🌟 CATWALK GENERATOR"
    puts "=" * 70
    puts "Subject: #{subject}"
    puts "Style: #{style}"
    puts "Lighting: #{lighting}"
    puts "=" * 70

    img_url = generate_image(prompt)
    return unless img_url

    img_file = File.join(@out, "catwalk_#{Time.now.strftime("%Y%m%d_%H%M%S")}.webp")
    download(img_url, img_file)

    motion_prompt = "Model walking forward on runway with confident stride, " \
                    "smooth catwalk motion, professional model walk, " \
                    "elegant movement, camera slowly tracking forward"

    vid_url = generate_video(img_url, motion_prompt, model: :hailuo)
    return unless vid_url

    vid_file = File.join(@out, "catwalk_#{Time.now.strftime("%Y%m%d_%H%M%S")}.mp4")
    download(vid_url, vid_file)

    if audio_path && File.exist?(audio_path)
      final_file = vid_file.gsub(".mp4", "_audio.mp4")
      system("ffmpeg -i "#{vid_file}" -i "#{audio_path}" -c:v copy -map 0:v:0 -map 1:a:0 -shortest "#{final_file}" -y 2>&1")
      puts "✓ Audio added: #{final_file}" if File.exist?(final_file)
    end

    puts "
" + "=" * 70
    puts "✨ CATWALK COMPLETE!"
    puts "=" * 70
    puts "📸 Image: #{img_file}"
    puts "🎬 Video: #{vid_file}"
  end

  def execute_chain(prompt = nil)

    prompt ||= "beautiful cinematic portrait, golden hour lighting, shallow depth of field, professional photography, warm tones, 85mm lens"

    puts "

🎬 CINEMATIC CHAIN: RA2 LORA → VIDEO"

    puts "="*70

    puts "Prompt: #{prompt}"

    puts "="*70

    puts "

[1/3] Generating image with RA2 LoRA..."

    res = api(:post, "/predictions", {

      version: "387d19ad57699a915fbb12f89e61ffae24a2b04a3d5f065b59281e929d533ae5",

      input: {

        prompt: prompt,

        aspect_ratio: "16:9",

        output_format: "webp",

        num_inference_steps: 50

      }

    })

    img_url = wait_for_completion(JSON.parse(res.body)["id"], "RA2 LoRA")

    return unless img_url

    img_filename = File.join(@out, "chain_image_#{Time.now.strftime("%Y%m%d_%H%M%S")}.webp")

    download(img_url, img_filename)

    puts "

[2/3] Finding best image-to-video model..."

    res = api(:get, "/collections/image-to-video")

    models = JSON.parse(res.body)["models"] || []

    video_model = models.max_by { |m| m["run_count"] || 0 }

    unless video_model

      puts "✗ No video models found"

      return

    end

    model_id = "#{video_model["owner"]}/#{video_model["name"]}"

    puts "Using: #{model_id} (#{video_model["run_count"]} runs)"

    puts "

[3/3] Generating video..."

    res = api(:post, "/predictions", {

      version: video_model["latest_version"]["id"],

      input: {

        image: img_url,

        prompt: prompt

      }

    })

    vid_url = wait_for_completion(JSON.parse(res.body)["id"], "Video generation")

    return unless vid_url

    vid_filename = File.join(@out, "chain_video_#{Time.now.strftime("%Y%m%d_%H%M%S")}.mp4")

    download(vid_url, vid_filename)

    puts "

" + "="*70

    puts "✨ CHAIN COMPLETE!"

    puts "="*70

    puts "Image: #{img_filename}"

    puts "Video: #{vid_filename}"

    puts "="*70

  end

  # ─────────────────────────────────────────────────────────────────────
  # WILD CHAIN MODE: Random multi-model pipeline for experimental outputs
  # ─────────────────────────────────────────────────────────────────────
  def wild_chain(prompt, steps: 5, seed: nil)
    seed ||= rand(1_000_000)
    srand(seed)

    puts "\n🎲 WILD CHAIN MODE"
    puts "="*70
    puts "Prompt: #{prompt}"
    puts "Steps: #{steps}"
    puts "Seed: #{seed} (use same seed to reproduce)"
    puts "="*70

    # Build random pipeline
    pipeline = build_wild_pipeline(steps)

    puts "\n📋 Generated Pipeline:"
    pipeline.each_with_index do |step, i|
      puts "  [#{i+1}] #{step[:category]} → #{step[:model][:name]}"
    end
    puts "="*70

    # Execute pipeline
    current_result = nil
    artifacts = []

    pipeline.each_with_index do |step, i|
      puts "\n[#{i+1}/#{steps}] #{step[:category].upcase}: #{step[:model][:name]}"

      result = execute_wild_step(step, prompt, current_result, i)

      if result
        current_result = result
        artifact = save_wild_artifact(result, step, i)
        artifacts << artifact if artifact
        puts "  ✓ Output: #{File.basename(artifact)}" if artifact
      else
        puts "  ✗ Step failed, continuing with previous result..."
      end

      sleep 2
    end

    # Summary
    puts "\n" + "="*70
    puts "🎲 WILD CHAIN COMPLETE!"
    puts "="*70
    puts "Seed: #{seed}"
    puts "Artifacts: #{artifacts.length}"
    artifacts.each { |a| puts "  📁 #{File.basename(a)}" }
    puts "\nReproduce: ruby repligen.rb wild '#{prompt}' --seed=#{seed}"
    puts "="*70

    { seed: seed, artifacts: artifacts, pipeline: pipeline.map { |s| s[:model][:name] } }
  end

  def build_wild_pipeline(steps)
    pipeline = []
    last_category = nil

    # First step is always image generation
    pipeline << { category: :image_gen, model: WILD_CHAIN[:image_gen].sample }

    # Remaining steps follow logical flow
    (steps - 1).times do
      # Weight categories based on what makes sense
      weights = {
        enhance: last_category == :image_gen ? 3 : 1,
        style: last_category == :image_gen ? 2 : 1,
        video_gen: last_category != :video_gen ? 4 : 0,
        colorgrade: last_category == :image_gen ? 2 : 0,
        audio: last_category == :video_gen ? 3 : 0
      }

      # Build weighted selection
      pool = []
      weights.each do |cat, weight|
        next if weight == 0 || WILD_CHAIN[cat].nil?
        weight.times { pool << cat }
      end

      category = pool.sample || :enhance
      model = WILD_CHAIN[category].sample
      pipeline << { category: category, model: model }
      last_category = category
    end

    pipeline
  end

  def execute_wild_step(step, prompt, previous_result, step_index)
    case step[:category]
    when :image_gen
      generate_image(prompt)
    when :video_gen
      return nil unless previous_result
      generate_video(previous_result, prompt, model: infer_video_model(step[:model][:model]))
    when :enhance, :style, :colorgrade
      return nil unless previous_result
      apply_model(step[:model][:model], previous_result, prompt)
    when :audio
      generate_audio(prompt, step[:model][:model])
    else
      previous_result
    end
  end

  def infer_video_model(model_path)
    case model_path
    when /kling/ then :kling
    when /sora/ then :sora
    when /wan/ then :wan
    when /luma/ then :luma
    else :hailuo
    end
  end

  def apply_model(model_path, input_url, prompt)
    puts "  ⚙️ Applying #{model_path}..."

    res = api(:post, "/models/#{model_path}/predictions", {
      input: {
        image: input_url,
        prompt: prompt
      }.compact
    })

    return nil unless res
    wait_for_completion(JSON.parse(res.body)["id"], File.basename(model_path))
  end

  def generate_audio(prompt, model_path)
    puts "  🎵 Generating audio..."

    res = api(:post, "/models/#{model_path}/predictions", {
      input: {
        prompt: prompt[0..200],
        duration: 10
      }
    })

    return nil unless res
    wait_for_completion(JSON.parse(res.body)["id"], "Audio")
  end

  def save_wild_artifact(result, step, index)
    return nil unless result

    ext = case step[:category]
          when :video_gen then ".mp4"
          when :audio then ".wav"
          else ".webp"
          end

    filename = File.join(@out, "wild_#{Time.now.strftime("%Y%m%d_%H%M%S")}_#{index+1}_#{step[:model][:name].downcase.gsub(/\s+/, '_')}#{ext}")
    download(result, filename)
    filename
  rescue
    nil
  end

  def setup_database

    require "sqlite3"

    @db = SQLite3::Database.new(@db_path)

    @db.execute <<-SQL

      CREATE TABLE IF NOT EXISTS models (

        id TEXT PRIMARY KEY,

        owner TEXT,

        name TEXT,

        description TEXT,

        run_count INTEGER,

        category TEXT,

        indexed_at INTEGER

      )

    SQL

    @db.execute <<-SQL

      CREATE TABLE IF NOT EXISTS collections (

        slug TEXT PRIMARY KEY,

        name TEXT,

        description TEXT,

        model_count INTEGER

      )

    SQL

  end

  def index_models

    setup_database

    puts "

📚 INDEXING REPLICATE MODELS"

    puts "="*70

    puts "

Fetching collections..."

    res = api(:get, "/collections")

    collections = JSON.parse(res.body)["results"] || []

    puts "Found #{collections.size} collections"

    total_models = 0

    collections.each_with_index do |coll, idx|

      puts "

[#{idx + 1}/#{collections.size}] #{coll["name"]}"

      @db.execute(

        "INSERT OR REPLACE INTO collections VALUES (?, ?, ?, ?)",

        [coll["slug"], coll["name"], coll["description"], 0]

      )

      res = api(:get, "/collections/#{coll["slug"]}")

      models = JSON.parse(res.body)["models"] || []

      models.each do |model|

        model_id = "#{model["owner"]}/#{model["name"]}"

        @db.execute(

          "INSERT OR REPLACE INTO models VALUES (?, ?, ?, ?, ?, ?, ?)",

          [

            model_id,

            model["owner"],

            model["name"],

            model["description"],

            model["run_count"] || 0,

            coll["slug"],

            Time.now.to_i

          ]

        )

      end

      @db.execute(

        "UPDATE collections SET model_count = ? WHERE slug = ?",

        [models.size, coll["slug"]]

      )

      total_models += models.size

      puts "  ✓ Indexed #{models.size} models"

      sleep 1

    end

    puts "

" + "="*70

    puts "✨ INDEXING COMPLETE"

    puts "="*70

    puts "Collections: #{collections.size}"

    puts "Models: #{total_models}"

    puts "Database: #{@db_path}"

    puts "="*70

  end

  def search_models(query)

    setup_database

    puts "

🔍 SEARCHING: #{query}"

    puts "="*70

    results = @db.execute(

      "SELECT id, description, category, run_count FROM models WHERE id LIKE ? OR description LIKE ? ORDER BY run_count DESC LIMIT 20",

      ["%#{query}%", "%#{query}%"]

    )

    if results.empty?

      puts "No results found"

    else

      results.each do |row|

        puts "

#{row[0]}"

        puts "  #{row[1][0..80]}..." if row[1]

        puts "  Category: #{row[2]}"

        puts "  Runs: #{row[3]}"

      end

      puts "

#{results.size} results"

    end

  end

  def generate_commercial(subject, lora: "ra2", model: :kling)

    puts "

🎬 TEAM NORWAY BEACH VOLLEYBALL COMMERCIAL"

    puts "LA 2028 Olympics | Professional Sports Cinematography"

    puts "="*70

    puts "Subject: #{subject}"

    puts "LoRA: #{lora}"

    puts "Video Model: #{model}"

    puts "Strategy: Advanced motion graphics with separated camera/subject motion"

    puts "="*70

    scenes = [

      {

        name: "hero_dolly_in",

        image_prompt: "Close-up portrait of RA2 woman as Norwegian beach volleyball athlete at LA 2028 Olympics, determined confident expression with subtle intensity in eyes, late afternoon golden hour sunlight from 45 degrees camera left creating warm rim light highlighting cheekbones and hair, red and blue Norwegian team uniform visible on shoulder, beach volleyball court and net softly blurred in background, shot on Zeiss Supreme Prime 85mm at T1.5 on ARRI Alexa Mini LF, natural skin texture with soft film grain, Kodak Vision3 500T color science",

        video_prompt: "Camera: Slow dolly-in from medium shot to close-up, smooth fluid motion maintaining focus on athlete's face. Subject: RA2 woman remains still with confident expression, slight natural breathing, wind gently moving hair strands. Golden hour lighting, shallow depth of field gradually intensifying, background softly defocusing. 35mm film aesthetic with natural grain.",

        duration: 10

      },

      {

        name: "powerful_serve",

        image_prompt: "Dynamic action shot of RA2 woman as Norwegian volleyball athlete mid-serve, athletic powerful motion frozen at peak moment of contact with ball, muscles engaged showing strength and grace, red and blue team uniform, LA 2028 Olympics beach court at golden hour, dramatic low angle perspective looking up, shot on Atlas Orion 40mm Anamorphic on ARRI Alexa Mini LF with signature oval bokeh and horizontal lens flares, cinematic 2.39:1 framing with teal and orange color grading",

        video_prompt: "Subject: RA2 athlete executes powerful volleyball serve, natural weight transfer from back foot to front, arm follows through with realistic momentum and follow-through motion, ball trajectory with natural physics. Camera: Tracking shot following the serve motion from low angle, maintaining athlete centered in frame. Slow motion 120fps simulated, dramatic sunset lighting with volleyball casting shadow, sand particles subtly disturbed by movement. Anamorphic lens flares during peak action.",

        duration: 10

      },

      {

        name: "team_huddle_orbit",

        image_prompt: "Norwegian women's beach volleyball team huddle at LA 2028 Olympics, four blonde athletes including RA2 in red white and blue uniforms, hands stacked together in center showing team unity, genuine smiles and emotional connection, warm golden hour backlight creating luminous rim lighting on hair and shoulders, shot on Cooke S4/i 50mm at T2.8 on ARRI Alexa Mini LF, natural authentic team moment with soft film grain and rich shadow detail",

        video_prompt: "Subject: Team of four athletes remains in huddle formation, natural micro-movements of breathing and subtle weight shifts, genuine smiles and eye contact between teammates showing authentic emotion. Camera: Smooth orbital movement circling around the huddle at 270 degrees, maintaining team centered, starting from behind and ending at front angle showing faces. Golden hour lighting with natural shadow play, Cooke lens characteristic warm rendering, documentary-style authenticity.",

        duration: 10

      },

      {

        name: "celebration_slow_motion",

        image_prompt: "RA2 woman as Norwegian volleyball athlete celebrating Olympic point victory, explosive joy with arms raised overhead in triumph, athletic physique mid-jump with genuine emotional expression, red and blue team uniform, sunset beach court with warm golden light, other teammates visible celebrating in soft focus background, shot on RED DRAGON 8K sensor with 70-200mm telephoto at f/2.8, ultra-sharp detail with natural motion blur on extremities",

        video_prompt: "Subject: RA2 athlete celebrates with natural explosive jump, arms raising with delayed follow-through showing realistic weight and momentum, hair responding to movement with natural physics, facial expression transitioning from intensity to pure joy with authentic micro-expressions. Camera: Static locked-down tripod shot capturing full celebration. Slow motion 240fps simulated showing every detail, golden hour backlight creating beautiful silhouette moments, sand particles catching light, teammates visible reacting in background. Natural depth of field, cinematic framing.",

        duration: 10

      },

      {

        name: "determined_closeup",

        image_prompt: "Extreme close-up of RA2 woman's eyes as Norwegian Olympic athlete, intense determined gaze directly into camera showing competitive focus, droplets of sweat visible on forehead catching golden hour light, natural skin texture and pores visible, shallow depth of field with only eyes in sharp focus, shot on ARRI Alexa Mini LF with Zeiss Supreme Prime 135mm at T1.8, intimate emotional connection, film grain texture",

        video_prompt: "Camera: Static camera, intimate locked-down shot maintaining eye contact. Subject: RA2 athlete's face remains mostly still showing athletic focus, natural micro-expressions in eyes showing determination, subtle breathing visible, slight head tilt showing confidence, single blink at natural timing. Golden hour lighting creating catch lights in eyes, sweat droplets glistening, wind subtly moving single hair strands. Emotional intensity building throughout shot. Professional sports documentary style.",

        duration: 10

      }

    ]

    clips = []

    total_cost = 0

    scenes.each_with_index do |scene, i|

      puts "

[#{i+1}/#{scenes.length}] #{scene[:name]}"

      puts "="*70

      # Generate image with detailed prompt

      puts "

📸 Image prompt (#{scene[:image_prompt].length} chars)"

      img = generate_image(scene[:image_prompt], lora: lora)

      next unless img

      # Generate video directly with motion-specific prompt

      # Modern video models (Kling 2.5) handle depth/motion natively

      puts "

🎬 Motion prompt (#{scene[:video_prompt].length} chars)"

      vid = generate_video(img, scene[:video_prompt], duration: scene[:duration], model: model)

      next unless vid

      # Download

      filename = File.join(@out, "scene_#{i+1}_#{scene[:name]}.mp4")

      download(vid, filename)

      clips << filename

      cost = model == :kling ? 0.52 : (model == :sora ? 2.02 : 0.32)

      total_cost += cost

      sleep 2

    end

    puts "

" + "="*70

    puts "✨ COMMERCIAL COMPLETE!"

    puts "="*70

    puts "Generated: #{clips.length}/#{scenes.length} professional cinema shots"

    puts "Total duration: #{clips.length * 10}s"

    puts "Total cost: $#{total_cost.round(2)}"

    puts "Output: #{@out}/"

    puts "

Advanced cinematography techniques applied:"

    puts "  ✓ Separated camera/subject motion in prompts"

    puts "  ✓ Realistic physics keywords (weight transfer, momentum)"

    puts "  ✓ Professional lens and camera specifications"

    puts "  ✓ Natural lighting with motivated sources"

    puts "  ✓ Film stock color science (Kodak Vision3)"

    puts "  ✓ Authentic micro-expressions and secondary motion"

    puts "  ✓ Speed modifiers (120fps/240fps slow motion simulation)"

  end

  def run(args)

    if args.empty?

      show_help

      return

    end

    command = args[0]

    case command

    when "generate", "g"

      prompt = args[1..-1].join(" ")

      if prompt.empty?

        puts "Usage: repligen.rb generate 'your natural language prompt'"

        return

      end

      img = generate_image(prompt)

      if img

        filename = File.join(@out, "image_#{Time.now.strftime("%Y%m%d_%H%M%S")}.webp")

        download(img, filename)

      end

    when "video", "v"

      prompt = args[1..-1].join(" ")

      if prompt.empty?

        puts "Usage: repligen.rb video 'your natural language prompt' [sora|kling|wan|hailuo]"

        return

      end

      # Check for model flag

      model = :hailuo

      if args[-1] =~ /^(sora|kling|wan|hailuo)$/

        model = args[-1].to_sym

        prompt = args[1..-2].join(" ")

      end

      img = generate_image(prompt)

      return unless img

      vid = generate_video(img, prompt, model: model)

      if vid

        filename = File.join(@out, "video_#{Time.now.strftime("%Y%m%d_%H%M%S")}.mp4")

        download(vid, filename)

        puts "

✨ Complete! 10s video with #{model}"

      end

    when "enhance", "e"

      subject = args[1] || "me2"

      enhance_training_photos(subject)

    when "catwalk", "cw"

      subject = args[1] || "beautiful blonde woman"

      style = args[2] || "haute_couture"

      lighting = args[3] || "runway"

      audio = args[4]

      generate_catwalk(subject, style: style, lighting: lighting, audio_path: audio)

    when "lora", "l"

      subject = args[1] || "me2"

      train_lora(subject)

    when "commercial", "c"

      subject = args[1] || "RA2 woman"

      lora = args[2] || "ra2"

      model = (args[3] || "kling").to_sym

      generate_commercial(subject, lora: lora, model: model)

    when "chain"

      prompt = args[1..-1].join(" ")

      execute_chain(prompt.empty? ? nil : prompt)

    when "wild", "w"

      # Parse args: wild 'prompt' --steps=N --seed=N
      prompt_parts = []
      steps = 5
      seed = nil

      args[1..-1].each do |arg|
        if arg =~ /^--steps=(\d+)$/
          steps = $1.to_i.clamp(2, 10)
        elsif arg =~ /^--seed=(\d+)$/
          seed = $1.to_i
        else
          prompt_parts << arg
        end
      end

      prompt = prompt_parts.join(" ")
      if prompt.empty?
        puts "Usage: repligen.rb wild 'your creative prompt' [--steps=5] [--seed=12345]"
        return
      end

      wild_chain(prompt, steps: steps, seed: seed)

    when "index", "i"

      index_models

    when "search", "s"

      query = args[1..-1].join(" ")

      if query.empty?

        puts "Usage: repligen.rb search 'query'"

        return

      end

      search_models(query)

    when "help", "h", "-h", "--help"

      show_help

    else

      puts "Unknown command: #{command}"

      show_help

    end

  end

  def show_help

    puts "

🎬 REPLIGEN v#{VERSION}"

    puts "Natural Language Cinematography + LoRA Training"

    puts "="*70

    puts "

Commands:"

    COMMANDS.each do |cmd, desc|

      puts "  #{cmd.ljust(15)} #{desc}"

    end

    puts "

Examples:"

    puts "  ruby repligen.rb generate 'Close-up portrait of woman, golden hour lighting'"

    puts "  ruby repligen.rb video 'Norwegian athlete serves volleyball at sunset beach'"

    puts "  ruby repligen.rb catwalk 'ME2 blonde model' haute_couture runway"

    puts "  ruby repligen.rb chain 'cinematic portrait with dramatic lighting'"

    puts "  ruby repligen.rb enhance me2"

    puts "  ruby repligen.rb lora me2"

    puts "  ruby repligen.rb commercial 'Team Norway' ra2"

    puts "  ruby repligen.rb index"

    puts "  ruby repligen.rb search 'video generation'"

    puts "

Catwalk styles: #{CATWALK_STYLES.keys.join(', ')}"

    puts "Catwalk lighting: #{CATWALK_LIGHTING.keys.join(', ')}"

    puts "

Principles:"

    puts "  • Use natural language, not keyword-stacking"

    puts "  • Describe cinematography: camera, lens, lighting"

    puts "  • Reference film stocks: Kodak Vision3 500T, Portra 400"

    puts "  • No quality tags like 'masterpiece' - they waste tokens"

    puts "  • 15-75 words optimal prompt length"

  end

end

if __FILE__ == $0

  Repligen.new.run(ARGV)

end
