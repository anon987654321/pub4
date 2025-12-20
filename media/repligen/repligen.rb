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
    "lora" => "Train custom LoRA from photos in __lora/{subject}/",
    "enhance" => "Enhance training photos (remove bg, sharpen, upscale)",
    "commercial" => "Generate multi-clip commercial with cinematography",
    "chain" => "Execute model chain (ra2 → video)",
    "index" => "Index Replicate models to local database",
    "search" => "Search indexed models",
    "help" => "Show this help"
  }

  def initialize
    @token = TOKEN
    @out = File.join(File.dirname(__FILE__), "repligen")
    @db_path = File.join(File.dirname(__FILE__), "repligen_models.db")
    FileUtils.mkdir_p(@out)
  end

  def api(method, path, body = nil)
    uri = URI("https://api.replicate.com/v1#{path}")
    req = method == :get ? Net::HTTP::Get.new(uri) : Net::HTTP::Post.new(uri)
    req["Authorization"] = "Token #{@token}"
    req["Content-Type"] = "application/json"
    req.body = body.to_json if body
    Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
  end

  def wait(id, name)
    print "⏳ #{name}..."
    loop do
      sleep 3
      res = api(:get, "/predictions/#{id}")
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
  end

  def download(url, filename)
    puts "📥 Downloading..."
    File.write(filename, Net::HTTP.get(URI(url)))
    puts "✓ Saved: #{filename}"
  end

  # === IMAGE GENERATION ===
  
  def generate_image(prompt, lora: nil)
    puts "
🎨 Generating image..."
    puts "Prompt: #{prompt[0..100]}..."
    
    if lora
      # Use custom LoRA
      res = api(:post, "/predictions", {
        version: "387d19ad57699a915fbb12f89e61ffae24a2b04a3d5f065b59281e929d533ae5",
        input: {
          prompt: prompt,
          aspect_ratio: "16:9",
          output_format: "webp",
          num_inference_steps: 35
        }
      })
    else
      # Use Flux Pro for best quality
      res = api(:post, "/models/black-forest-labs/flux-pro/predictions", {
        input: {
          prompt: prompt,
          aspect_ratio: "16:9",
          output_format: "webp"
        }
      })
    end
    
    wait(JSON.parse(res.body)["id"], lora ? "RA2 LoRA" : "Flux Pro")
  end

  # === VIDEO EXTENSION ===
  
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
    
    wait(JSON.parse(res.body)["id"], "Luma Extend")
  end

  # === VIDEO GENERATION ===
  
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
      wait(JSON.parse(res.body)["id"], "Sora 2 #{duration}s")
      
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
      wait(JSON.parse(res.body)["id"], "Kling 2.5 Pro #{duration}s")
      
    when :wan
      # Wan 2.5 - open source, audio sync, 109K runs (affordable)
      res = api(:post, "/models/wan-video/wan-2.5-i2v/predictions", {
        input: {
          image: image_url,
          prompt: prompt,
          duration: duration
        }
      })
      wait(JSON.parse(res.body)["id"], "Wan 2.5 #{duration}s")
      
    else
      # Minimax Hailuo 2.3 - default, good motion (affordable)
      res = api(:post, "/models/minimax/video-01/predictions", {
        input: {
          prompt: prompt,
          first_frame_image: image_url,
          prompt_optimizer: true
        }
      })
      wait(JSON.parse(res.body)["id"], "Hailuo 2.3 10s")
    end
  end

  # === IMAGE ENHANCEMENT ===
  
  def enhance_for_video(image_url, name)
    puts "
  🔧 Enhancing image for better video quality..."
    
    # 1. Generate depth map for better 3D motion
    puts "  [1/3] Depth map generation..."
    res = api(:post, "/models/adirik/depth-anything-v2/predictions", {
      input: { image: image_url }
    })
    depth = wait(JSON.parse(res.body)["id"], "Depth")
    
    # 2. Edge refinement with canny
    puts "  [2/3] Edge refinement..."
    res = api(:post, "/models/jagilley/controlnet-canny/predictions", {
      input: { 
        image: image_url,
        prompt: "high quality, sharp edges, professional photography",
        num_inference_steps: 20
      }
    })
    refined = wait(JSON.parse(res.body)["id"], "Edge Refine")
    
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
    enhanced = wait(JSON.parse(res.body)["id"], "Relight")
    
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

  # === LORA TRAINING ===
  
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

  # === CHAIN EXECUTION ===
  
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
    
    img_url = wait(JSON.parse(res.body)["id"], "RA2 LoRA")
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
    
    vid_url = wait(JSON.parse(res.body)["id"], "Video generation")
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
  
  # === MODEL INDEXING ===
  
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
  
  # === COMMERCIAL GENERATOR ===
  
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

  # === MAIN ROUTER ===
  
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
    puts "  ruby repligen.rb chain 'cinematic portrait with dramatic lighting'"
    puts "  ruby repligen.rb enhance me2"
    puts "  ruby repligen.rb lora me2"
    puts "  ruby repligen.rb commercial 'Team Norway' ra2"
    puts "  ruby repligen.rb index"
    puts "  ruby repligen.rb search 'video generation'"
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
