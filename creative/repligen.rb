#!/usr/bin/env ruby
# frozen_string_literal: true

require "net/http"
require "json"
require "logger"
require "optparse"
require "fileutils"

# Repligen - AI Content Generation with Postpro Integration  
# Version: 8.1.0 - Dynamic Model Discovery + Working Image-to-Video
#
# PROVEN WORKFLOW (Dec 2025):
# 1. Query /v1/collections/image-to-video for current models
# 2. Use first available model with latest_version.id
# 3. Convert image to base64 data URI
# 4. Poll prediction status every 10s
# 5. Download output from replicate.delivery URL
#
# WORKING COMMAND:
# $coll = GET /v1/collections/image-to-video
# $model = $coll.models[0]
# $version = $model.latest_version.id
# POST /v1/predictions with {version, input: {image: data:image/*;base64,...}}
#
# See execute_simple_generation() for working implementation

module Bootstrap
  def self.dmesg(msg)
    puts "[repligen] #{msg}"
  end

  def self.startup_banner
    ruby_version = RUBY_VERSION
    os = RbConfig::CONFIG["host_os"]
    pwd = Dir.pwd
    dmesg "boot ruby=#{ruby_version} os=#{os} pwd=#{pwd}"
  end

  def self.ensure_sqlite3
    require "sqlite3"
    dmesg "OK sqlite3 gem present"
    true
  rescue LoadError
    dmesg "WARN sqlite3 gem missing, attempting install..."
    begin
      if system("gem install sqlite3 --no-document")
        require "sqlite3"
        dmesg "OK sqlite3 gem installed"
        true
      else
        dmesg "WARN sqlite3 install failed, fallback to JSONL logging"
        false
      end
    rescue => e
      dmesg "WARN sqlite3 unavailable: #{e.message}, using JSONL fallback"
      false
    end
  end

  def self.ensure_ferrum
    require "ferrum"
    dmesg "OK ferrum gem present"
    true
  rescue LoadError
    dmesg "WARN ferrum gem missing, attempting install..."
    begin
      if system("gem install ferrum --no-document")
        require "ferrum"
        dmesg "OK ferrum gem installed"
        true
      else
        dmesg "WARN ferrum install failed, web scraping disabled"
        false
      end
    rescue => e
      dmesg "WARN ferrum unavailable: #{e.message}"
      false
    end
  end

  def self.ensure_token
    return ENV["REPLICATE_API_TOKEN"] if ENV["REPLICATE_API_TOKEN"]

    config_dir = File.expand_path("~/.config/repligen")
    config_file = File.join(config_dir, "config.json")

    if File.exist?(config_file)
      begin
        config = JSON.parse(File.read(config_file))
        token = config["api_token"]
        if token && !token.empty?
          ENV["REPLICATE_API_TOKEN"] = token
          dmesg "OK REPLICATE_API_TOKEN loaded from user config"
          return token
        end
      rescue => e
        dmesg "WARN config file corrupted: #{e.message}"
      end
    end

    if $stdin.tty?
      dmesg "PROMPT Enter REPLICATE_API_TOKEN (from https://replicate.com/account):"
      print "Token: "
      token = gets.chomp.strip

      if token && !token.empty?
        FileUtils.mkdir_p(config_dir)
        config = { "api_token" => token }
        File.write(config_file, JSON.pretty_generate(config))
        File.chmod(0600, config_file)
        ENV["REPLICATE_API_TOKEN"] = token
        dmesg "OK token saved to user config (#{config_file})"
        return token
      end
    end

    dmesg "ERROR no REPLICATE_API_TOKEN available"
    nil
  end

  def self.ensure_anthropic_token
    return ENV["ANTHROPIC_API_KEY"] if ENV["ANTHROPIC_API_KEY"]

    config_dir = File.expand_path("~/.config/repligen")
    config_file = File.join(config_dir, "config.json")

    if File.exist?(config_file)
      begin
        config = JSON.parse(File.read(config_file))
        token = config["anthropic_api_key"]
        if token && !token.empty?
          ENV["ANTHROPIC_API_KEY"] = token
          dmesg "OK ANTHROPIC_API_KEY loaded from user config"
          return token
        end
      rescue => e
        dmesg "WARN config parse error: #{e.message}"
      end
    end

    dmesg "WARN ANTHROPIC_API_KEY not found, Claude vision disabled"
    nil
  end

  def self.load_master_config
    return {} unless File.exist?("master.json")
    
    begin
      master = JSON.parse(File.read("master.json").gsub(/^.*\/\/.*$/, ""))
      config = master.dig("config", "multimedia", "repligen") || {}
      dmesg "OK loaded defaults from master.json"
      config
    rescue => e
      dmesg "WARN failed to parse master.json: #{e.message}"
      {}
    end
  end

  def self.run
    startup_banner
    sqlite_available = ensure_sqlite3
    ferrum_available = ensure_ferrum
    token = ensure_token
    anthropic_token = ensure_anthropic_token
    config = load_master_config

    {
      sqlite_available: sqlite_available,
      ferrum_available: ferrum_available,
      token: token,
      anthropic_token: anthropic_token,
      config: config
    }

  end
end
class Repligen
  API = 'https://api.replicate.com/v1'
  
  MODELS = {
    # NOTE: Use discover/search commands to get current working models!
    # Model IDs change frequently on Replicate. These are placeholders.
    # Real workflow: query collections/image-to-video for actual working models
    
    # Image Generation - Latest & Best (Dec 2024)
    flux_pro: 'black-forest-labs/flux-2-pro',
    flux_dev: 'black-forest-labs/flux-dev',
    flux_schnell: 'black-forest-labs/flux-schnell',
    imagen3: 'google-deepmind/imagen-3',
    imagen4: 'google/imagen-4',
    seedream: 'bytedance/seedream-4.5',
    ideogram: 'ideogram-ai/ideogram-v3-turbo',
    sdxl: 'stability-ai/sdxl:7762fd07cf82c948538e41f63f77d685e02b063e37e496e96eefd46c929f9bdc',
    
    # Image-to-Video - IMPORTANT: Query API dynamically!
    # These model IDs are often invalid. Use: GET /v1/collections/image-to-video
    kling: 'kuaishou/kling-video-v2.1',
    luma: 'lumalabs/ray2',
    veo: 'google/veo-3.1',
    sora: 'openai/sora-2',
    hailuo: 'minimax/video-01',
    hailuo_fast: 'minimax/hailuo-2.3-fast',
    seedance_pro: 'bytedance/seedance-1-pro',
    seedance_fast: 'bytedance/seedance-1-fast',
    runway: 'runwayml/gen-4-image',
    wan720: 'alibaba-pai/wan-video-i2v-720p',
    wan1080: 'alibaba-pai/wan-video-i2v-1080p',
    
    # Enhancement & Upscaling
    upscale: 'nightmareai/real-esrgan:f121d640bd286e1fdc67f9799164c1d5be36ff74576ee11c803ae5b665dd46aa',
    upscale_video: 'topazlabs/video-upscale',
    upscale_topaz: 'topazlabs/image-upscale',
    crystal: 'philz1337x/crystal-upscaler',
    clarity: 'philz1337x/clarity-upscaler',
    
    # Audio & Music  
    music: 'meta/musicgen-stereo-large',
    speech: 'minimax/speech-02-turbo',
    chatterbox: 'ressemble-ai/chatterbox-multilingual',
    kokoro: 'jaaari/kokoro-82m',
    transcribe: 'openai/gpt-4o-transcribe',
    
    # Utility
    depth: 'fofr/depth-anything-v2',
    rembg: 'lucataco/remove-bg',
    rembg_video: 'arielreplicate/robust_video_matting',
    ocr: 'datalab-to/marker',
    lora: 'ostris/flux-dev-lora-trainer'
  }.freeze
  
  COSTS = { 
    # Image models
    flux_pro: 0.04, flux_dev: 0.025, flux_schnell: 0.003, imagen3: 0.01, imagen4: 0.015,
    seedream: 0.03, ideogram: 0.04, sdxl: 0.02,
    
    # Video models
    kling: 0.15, luma: 0.12, veo: 0.20, sora: 0.30, 
    hailuo: 0.08, hailuo_fast: 0.05, seedance_pro: 0.15, seedance_fast: 0.08,
    runway: 0.10, wan720: 0.06, wan1080: 0.10,
    
    # Enhancement
    upscale: 0.002, upscale_video: 0.01, upscale_topaz: 0.008, crystal: 0.015, clarity: 0.01,
    
    # Audio
    music: 0.02, speech: 0.01, chatterbox: 0.015, kokoro: 0.005, transcribe: 0.006,
    
    # Utility
    depth: 0.005, rembg: 0.002, rembg_video: 0.008, ocr: 0.003, lora: 1.46
  }.freeze
  
  CHAINS = {
    # Quick Image Chains
    quick: %w[flux_schnell upscale],
    image_pro: %w[flux_pro clarity],
    ultra_image: %w[seedream upscale_topaz],
    
    # Video Chains - Cinematic Quality
    hollywood: %w[flux_pro clarity kling music],
    cinematic: %w[flux_pro crystal luma speech],
    ultra_hd: %w[imagen4 upscale_topaz veo chatterbox],
    premium: %w[seedream crystal sora music],
    anime: %w[ideogram upscale kling],
    
    # Fast Prototyping  
    fast_video: %w[flux_schnell wan720],
    budget: %w[imagen3 wan720 music],
    speed: %w[flux_schnell hailuo_fast kokoro],
    
    # Advanced Pipelines
    masterpiece: %w[flux_pro depth crystal luma chatterbox],
    experimental: %w[seedream rembg upscale kling music],
    multi_angle: %w[flux_pro depth clarity kling runway music],
    professional: %w[imagen4 upscale_topaz seedance_pro speech],
    
    # Chaos mode
    chaos: -> { MODELS.keys.sample(rand(8..15)) }
  }.freeze

  def initialize(token = nil)
    @bootstrap = Bootstrap.run
    @token = token || @bootstrap[:token]
    @logger = Logger.new($stderr, level: ENV["DEBUG"] ? Logger::DEBUG : Logger::WARN)
    @config = @bootstrap[:config]
    
    if @bootstrap[:sqlite_available]
      @db = init_db
      @storage_mode = :sqlite
    else
      @db = nil
      @storage_mode = :jsonl
      @jsonl_file = "repligen_chains.jsonl"
    end
    
    @postpro = File.exist?("postpro.rb")
  end

  def run(cmd = nil, *args)
    return auth_error unless @token
    
    case cmd
    when "scrape"
      scrape_replicate_explore
    else
      interactive_cli
    end
  end
  
  def scrape_replicate_explore
    unless @bootstrap[:ferrum_available]
      Bootstrap.dmesg "ERROR ferrum gem required for scraping. Install: gem install ferrum"
      return false
    end
    
    require "ferrum"
    Bootstrap.dmesg "scrape replicate.com/explore starting..."
    
    browser = Ferrum::Browser.new(headless: true, timeout: 30)
    page_count = 0
    model_count = 0
    
    begin
      ["trending", "featured", "image-to-text", "text-to-image", "image-to-video", "text-to-video", "text-to-speech", "speech-to-text"].each do |category|
        url = "https://replicate.com/explore/#{category}"
        Bootstrap.dmesg "scrape category=#{category}"
        
        browser.goto(url)
        sleep 2
        
        browser.execute("window.scrollTo(0, document.body.scrollHeight)")
        sleep 1
        
        models = browser.css("a[href*='/']").map do |link|
          href = link.attribute("href")
          next unless href&.match?(/^\/[^\/]+\/[^\/]+$/)
          
          text = link.text.strip
          next if text.empty?
          
          { url: "https://replicate.com#{href}", text: text }
        end.compact.uniq
        
        models.each do |model|
          next unless model[:url].match?(/replicate\.com\/([^\/]+)\/([^\/]+)$/)
          
          owner = $1
          name = $2
          
          if @db
            existing = @db.execute("SELECT id FROM models WHERE owner = ? AND name = ?", [owner, name])
            next unless existing.empty?
            
            @db.execute("INSERT INTO models (owner, name, description, url, created_at) VALUES (?, ?, ?, ?, ?)",
                       [owner, name, model[:text], model[:url], Time.now.to_i])
            model_count += 1
          end
        end
        
        page_count += 1
        Bootstrap.dmesg "scraped page=#{page_count} models_found=#{models.size} models_saved=#{model_count}"
      end
      
      Bootstrap.dmesg "scrape complete pages=#{page_count} models=#{model_count}"
      true
    rescue => e
      Bootstrap.dmesg "ERROR scrape failed: #{e.message}"
      false
    ensure
      browser.quit
    end
  end

  def default_chain
    (@config["default_chain"] || "quick").to_sym
  end

  def autorun_default
    Bootstrap.dmesg "autorun mode: #{default_chain} chain"
    result = chain_and_offer(default_chain, "digital art")
    
    if result && @postpro && !$stdin.tty?
      Bootstrap.dmesg "launching postpro.rb --from-repligen --auto"
      system("ruby postpro.rb --from-repligen --auto")
    end
    
    result
  end

  private

  def auth_error
    puts "Set REPLICATE_API_TOKEN. Get token at https://replicate.com/account"
    exit 1
  end

  def init_db
    return nil unless @bootstrap[:sqlite_available]
    
    begin
      require "sqlite3"
      SQLite3::Database.new("repligen.db").tap do |db|
        db.execute("CREATE TABLE IF NOT EXISTS chains (id INTEGER PRIMARY KEY, models TEXT, cost REAL, created_at INTEGER)")
        db.execute("CREATE TABLE IF NOT EXISTS models (id INTEGER PRIMARY KEY, owner TEXT, name TEXT, description TEXT, runs INTEGER, url TEXT, created_at INTEGER)")
      end
    rescue => e
      Bootstrap.dmesg "WARN sqlite3 initialization failed: #{e.message}"
      nil
    end
  end

  def log_chain(models, cost)
    if @storage_mode == :sqlite && @db
      @db.execute("INSERT INTO chains (models, cost, created_at) VALUES (?, ?, ?)", 
                  [models.join(","), cost, Time.now.to_i])
    else
      log_entry = {
        models: models,
        cost: cost,
        timestamp: Time.now.iso8601
      }
      File.open(@jsonl_file, "a") { |f| f.puts JSON.generate(log_entry) }
    end
  end

  def request(endpoint, method = :get, body = nil)
    uri = URI("#{API}/#{endpoint}")
    req = method == :post ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
    req['Authorization'] = "Token #{@token}"
    req['Content-Type'] = 'application/json'
    req.body = body.to_json if body

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 300) { |http| http.request(req) }
    raise "API Error: #{response.code} #{response.body}" unless response.code.to_i.between?(200, 299)
    
    JSON.parse(response.body)
  end

  def predict(model_key, input)
    model, version = MODELS[model_key].split(':')
    
    pred = request('predictions', :post, {
      version: version,
      input: format_input(model_key, input),
      webhook: ENV['WEBHOOK_URL']
    })
    
    wait_for(pred['id'])
  end

  def wait_for(id, timeout = 600)
    start = Time.now
    
    loop do
      pred = request("predictions/#{id}")
      
      case pred['status']
      when 'succeeded' then return pred['output']
      when 'failed' then raise pred['error']
      when 'canceled' then raise 'Canceled'
      end
      
      raise 'Timeout' if Time.now - start > timeout
      
      print '.'
      sleep 2
    end
  end

  def format_input(model, input)
    case model
    # Image Generation Models
    when :flux_pro, :flux_dev, :flux_schnell, :imagen3, :imagen4, :seedream, :ideogram, :sdxl
      { prompt: input.is_a?(String) ? input : 'cinematic masterpiece', num_outputs: 1 }
    
    # Image-to-Video Models (State of the Art Dec 2024)
    when :kling
      if input.start_with?('http')
        { image: input, duration: 10, fps: 24, prompt: 'smooth cinematic camera movement' }
      else
        { prompt: input, duration: 10, fps: 24 }
      end
    
    when :luma
      if input.start_with?('http')
        { image: input, loop: false, keyframes: { frame0: { type: 'image', url: input } } }
      else
        { prompt: input }
      end
    
    when :veo, :sora
      if input.start_with?('http')
        { image: input, prompt: 'dynamic cinematic movement', length: 8 }
      else
        { prompt: input, length: 8 }
      end
    
    when :hailuo, :hailuo_fast
      if input.start_with?('http')
        { image: input, prompt: 'smooth realistic motion', duration: 6 }
      else
        { prompt: input, duration: 6 }
      end
    
    when :seedance_pro, :seedance_fast
      if input.start_with?('http')
        { image: input, duration: 5, fps: 24 }
      else
        { prompt: input, duration: 5 }
      end
    
    when :wan720, :wan1080
      if input.start_with?('http')
        { image: input, num_frames: 81, fps: 16 }
      else
        { prompt: input, num_frames: 81 }
      end
    
    when :runway
      { image: input, duration: 5, fps: 24 }
    
    # Enhancement Models
    when :upscale, :upscale_topaz
      { image: input, scale: 4 }
    
    when :upscale_video
      { video: input, scale: 2 }
    
    when :crystal, :clarity
      { image: input, creativity: 0.35, resemblance: 0.6 }
    
    when :depth
      { image: input }
    
    when :rembg, :rembg_video
      { image: input }
    
    when :ocr
      { file: input }
    
    # Audio Models  
    when :music
      { prompt: input.is_a?(String) ? input : 'epic cinematic orchestral', duration: 10 }
    
    when :speech, :chatterbox, :kokoro
      { text: input.is_a?(String) ? input : 'Amazing cinematic video' }
    
    when :transcribe
      { audio: input }
    
    # Training
    when :lora
      { input_images: input.is_a?(Array) ? input.join(',') : input, trigger_word: 'subject', steps: 1000 }
    
    else
      { input: input }
    end
  end

  def chain(type, prompt)
    models = chain_for(type)
    puts "Running #{models.length}-step chain..."
    
    output = prompt
    cost = 0.0
    
    models.each_with_index do |model, i|
      puts "Step #{i + 1}: #{model}"
      output = predict(model.to_sym, output)
      cost += COSTS[model.to_sym]
    end
    
    log_chain(models, cost)
    
    puts "\nComplete! Cost: $%.3f" % cost
    
    save_output(output, type, prompt) if output.is_a?(String) && output.start_with?("http")
    output
  end

  def save_output(url, type, prompt)
    uri = URI(url)
    response = Net::HTTP.get_response(uri)
    
    return unless response.code == '200'
    
    # Determine output directory based on type
    dir = case type.to_s
    when /video|kling|luma|veo|wan|hailuo|runway/ then 'output/videos'
    when /audio|music/ then 'output/audio'
    else 'output/images'
    end
    
    FileUtils.mkdir_p(dir)
    
    # Determine file extension
    ext = url.match(/\.(mp4|mov|webm|mp3|wav|jpg|png|gif)$/i)&.captures&.first || 'jpg'
    
    filename = File.join(dir, "#{sanitize(prompt)}_#{type}_#{Time.now.strftime('%Y%m%d_%H%M%S')}.#{ext}")
    File.write(filename, response.body)
    puts "💾 Saved: #{filename}"
    File.utime(Time.now, Time.now, filename)
  rescue StandardError => e
    puts "⚠️  Could not save output: #{e.message}"
  end

  def sanitize(prompt)
    prompt.to_s.gsub(/[^\w\-_]/, '_').slice(0, 20)
  end

  def chain_for(type)
    CHAINS[type].respond_to?(:call) ? CHAINS[type].call : CHAINS[type]
  end

  def generate(prompt)
    chain(:quick, prompt)
  end

  def gen_and_offer(prompt)
    result = generate(prompt)
    offer_postpro if @postpro && result
    result
  end

  def chain_and_offer(type, prompt)
    result = chain(type, prompt)
    offer_postpro if @postpro && result
    result
  end

  def train_lora(urls)
    raise 'Provide image URLs' if urls.empty?
    
    puts 'Training LoRA...'
    output = predict(:lora, urls)
    puts "Model: #{output}"
    output
  end

  def cost(chain_type)
    chain_for(chain_type).sum { |m| COSTS[m.to_sym] }
  end

  def offer_postpro
    if $stdin.tty?
      puts "\nPostpro.rb detected! Want to apply cinematic processing?"
      print "Launch postpro? (Y/n): "
      
      response = gets.chomp.downcase
      if response.empty? || response.start_with?("y")
        puts "Launching postpro.rb with masterpiece presets..."
        system("ruby postpro.rb --from-repligen")
      else
        puts "Run 'ruby postpro.rb' later to process generated images"
      end
    else
      Bootstrap.dmesg "non-interactive mode, skipping postpro offer"
    end
  end

  def interactive
    puts "\nRepligen Interactive Mode"
    puts "Commands: (g)enerate, (c)hain, (d)iscover, (s)earch, (l)ist, info, cost, quit"
    puts "Postpro.rb integration: Active" if @postpro
    
    loop do
      print "> "
      input = gets&.chomp&.split || []
      cmd = input.shift
      
      handle_cmd(cmd, input)
    rescue => e
      puts "Error: #{e.message}"
      @logger.debug e.backtrace.join("\n")
    end
  end

  def handle_cmd(cmd, args)
    case cmd
    when 'g', 'generate' then gen_and_offer(args.empty? ? 'digital art' : args.join(' '))
    when 'c', 'chain' then chain_and_offer(args[0]&.to_sym || :quick, args[1..-1]&.join(' ') || 'art')
    when 'l', 'lora' then train_lora(args)
    when 'cost' then puts "$%.3f" % cost(args[0]&.to_sym || :quick)
    when 'postpro', 'p'
      @postpro ? system('ruby postpro.rb') : puts("postpro.rb not found")
    when 'discover', 'd' then discover_models(args)
    when 'search', 's' then search_models(args.join(' '))
    when 'add' then add_custom_model(args)
    when 'list' then list_models(args[0])
    when 'info' then show_model_info(args[0])
    when 'q', 'quit' then exit
    else puts "Unknown: #{cmd}"
    end
  end

  def discover_models(args = [])
    puts "\n🔍 Discovering models from Replicate API..."
    
    categories = args.empty? ? ['trending', 'featured'] : args
    discovered = []
    
    categories.each do |category|
      puts "\n📂 Category: #{category}"
      
      begin
        # Use Replicate API to get models
        endpoint = case category
        when 'trending' then 'models'
        when 'featured' then 'collections/featured'
        else "collections/#{category}"
        end
        
        response = request(endpoint, :get)
        models = response['results'] || response['models'] || []
        
        models.first(20).each do |model|
          owner = model['owner']
          name = model['name']
          url = model['url']
          description = model['description']
          runs = model['run_count'] || 0
          
          discovered << {
            id: "#{owner}/#{name}",
            owner: owner,
            name: name,
            description: description,
            runs: runs,
            url: url
          }
          
          puts "  ✓ #{owner}/#{name} (#{runs} runs)"
        end
        
      rescue => e
        puts "  ⚠️  Error fetching #{category}: #{e.message}"
      end
    end
    
    # Save to database
    if @db && discovered.any?
      discovered.each do |model|
        @db.execute(
          "INSERT OR REPLACE INTO models (owner, name, description, runs, url, created_at) VALUES (?, ?, ?, ?, ?, ?)",
          [model[:owner], model[:name], model[:description], model[:runs], model[:url], Time.now.to_i]
        )
      end
      puts "\n💾 Saved #{discovered.size} models to database"
    end
    
    discovered
  end

  def search_models(query)
    puts "\n🔍 Searching Replicate for: #{query}"
    
    begin
      # Search via API
      response = request("models?search=#{URI.encode_www_form_component(query)}", :get)
      results = response['results'] || []
      
      if results.empty?
        puts "No models found"
        return
      end
      
      puts "\n📋 Found #{results.size} models:\n"
      results.first(10).each_with_index do |model, i|
        puts "#{i+1}. #{model['owner']}/#{model['name']}"
        puts "   #{model['description']&.slice(0, 60)}..."
        puts "   Runs: #{model['run_count'] || 0}"
        puts
      end
      
    rescue => e
      puts "⚠️  Search failed: #{e.message}"
    end
  end
  
  def add_custom_model(args)
    if args.size < 2
      puts "Usage: add <name> <owner/model> [cost]"
      return
    end
    
    name = args[0].to_sym
    model_id = args[1]
    cost = args[2]&.to_f || 0.05
    
    if MODELS[name]
      puts "⚠️  Model #{name} already exists"
      return
    end
    
    puts "Adding custom model: #{name} -> #{model_id} ($#{cost})"
    
    # This would need to modify the source file or use a runtime registry
    # For now, just show what would be added
    puts "✓ To permanently add, edit MODELS hash in repligen.rb"
    puts "  #{name}: '#{model_id}',"
  end
  
  def list_models(category = nil)
    puts "\n📚 Available Models (#{MODELS.size} total):\n"
    
    models_by_type = {
      image: [:flux_pro, :flux_dev, :flux_schnell, :imagen3, :imagen4, :seedream, :ideogram, :sdxl],
      video: [:kling, :luma, :veo, :sora, :hailuo, :hailuo_fast, :seedance_pro, :seedance_fast, :runway, :wan720, :wan1080],
      upscale: [:upscale, :upscale_video, :upscale_topaz, :crystal, :clarity],
      audio: [:music, :speech, :chatterbox, :kokoro, :transcribe],
      utility: [:depth, :rembg, :rembg_video, :ocr, :lora]
    }
    
    filter = category&.to_sym
    models_by_type.each do |type, models|
      next if filter && type != filter
      
      puts "#{type.to_s.upcase}:"
      models.each do |m|
        next unless MODELS[m]
        cost = COSTS[m] || 0
        puts "  • #{m} - $#{cost}"
      end
      puts
    end
  end
  
  # WORKING METHOD: Use dynamic collection query instead of hardcoded models
  def generate_video_from_image(image_path, prompt = "cinematic epic camera movement")
    puts "🎬 Generating video from: #{image_path}"
    
    # Step 1: Get current working model from collection
    response = request('collections/image-to-video', :get)
    models = response['models'] || []
    
    if models.empty?
      puts "❌ No image-to-video models available"
      return nil
    end
    
    model = models.first
    version = model['latest_version']['id']
    puts "Using: #{model['owner']}/#{model['name']}"
    
    # Step 2: Convert image to base64 data URI
    image_data = File.read(image_path)
    image_b64 = [image_data].pack('m0')
    ext = File.extname(image_path).delete('.')
    data_uri = "data:image/#{ext};base64,#{image_b64}"
    
    # Step 3: Create prediction
    pred = request('predictions', :post, {
      version: version,
      input: {
        image: data_uri,
        prompt: prompt
      }
    })
    
    puts "⏱️  Prediction: #{pred['id']} (ETA: 2-3min)"
    
    # Step 4: Poll for completion
    output_url = wait_for(pred['id'], 600)
    
    # Step 5: Download result
    if output_url
      ext = output_url.match(/\.(\w+)(\?|$)/)&.captures&.first || 'mp4'
      base = File.basename(image_path, '.*')
      output_file = "#{base}_cinematic.#{ext}"
      
      uri = URI(output_url)
      response = Net::HTTP.get_response(uri)
      File.write(output_file, response.body)
      
      puts "✅ DONE: #{output_file}"
      output_file
    else
      nil
    end
  end

  def show_model_info(model_name)
    return puts "Usage: info <model_name>" unless model_name
    
    model = model_name.to_sym
    unless MODELS[model]
      puts "⚠️  Model not found: #{model}"
      return
    end
    
    puts "\n📊 Model Info: #{model}"
    puts "━"*50
    puts "ID:   #{MODELS[model]}"
    puts "Cost: $#{COSTS[model] || 'unknown'}"
    
    # Show which chains use it
    chains = CHAINS.select { |_, models| 
      models.is_a?(Array) && models.include?(model.to_s)
    }.keys
    
    if chains.any?
      puts "Used in chains: #{chains.join(', ')}"
    end
    puts
  end
end

if __FILE__ == $0
  OptionParser.new do |opts|
    opts.banner = 'Usage: repligen.rb [command] [args]'
    opts.on('-t TOKEN', '--token TOKEN', 'API token') { |t| ENV['REPLICATE_API_TOKEN'] = t }
    opts.on('-d', '--debug', 'Debug mode') { ENV['DEBUG'] = '1' }
    opts.on('-h', '--help', 'Show help') { puts opts; exit }
  end.parse!
  
  begin
    Repligen.new.run(ARGV[0], *ARGV[1..-1])
  rescue Interrupt
    puts "\nBye"
  rescue => e
    puts "Fatal: #{e.message}"
    puts e.backtrace if ENV['DEBUG']
    exit 1
  end
end

# Replicate model discovery via Ferrum + GPT-4 Vision
class ReplicateExplorer
  def initialize(anthropic_token, db = nil)
    @anthropic_token = anthropic_token
    @browser = nil
    @db = db || init_db
    @models = load_from_db
  end

  def init_db
    require "sqlite3"
    db = SQLite3::Database.new("repligen_models.db")
    db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS models (
        id TEXT PRIMARY KEY,
        type TEXT,
        description TEXT,
        cost REAL,
        documentation TEXT,
        discovered_at INTEGER
      )
    SQL
    db
  rescue LoadError
    Bootstrap.dmesg "WARN sqlite3 unavailable, models won't persist"
    nil
  end

  def discover(max_pages: 5)
    return [] unless setup_browser
    Bootstrap.dmesg "discovering models from replicate.com/explore"

    discovered = []
    begin
      @browser.goto("https://www.replicate.com/explore")
      sleep rand(3..7)

      max_pages.times do |page|
        html = @browser.body
        screenshot = screenshot_page(page)

        if screenshot && @anthropic_token
          models = extract_via_gpt4v(screenshot, html)
          discovered.concat(models) if models
          Bootstrap.dmesg "page #{page+1}: #{models&.size || 0} models"
        end

        break unless next_page
        sleep rand(3..7)
      end

      discovered.each { |m| save_model_to_db(m) }
      @models = load_from_db
      discovered
    rescue => e
      Bootstrap.dmesg "ERROR discovery: #{e.message}"
      []
    ensure
      cleanup
    end
  end

  def build_radical_chain(style: "cinematic", length: 5)
    return [] if @models.empty?

    categories = {
      image: @models.values.select { |m| m["type"] =~ /image|art/i },
      video: @models.values.select { |m| m["type"] =~ /video|motion/i },
      audio: @models.values.select { |m| m["type"] =~ /audio|music/i },
      enhance: @models.values.select { |m| m["type"] =~ /upscale|enhance/i },
      style: @models.values.select { |m| m["type"] =~ /style|artistic/i }
    }

    chain = case style
    when "cinematic"
      [categories[:image].sample, categories[:style].sample,
       categories[:enhance].sample, categories[:video].sample,
       categories[:audio].sample].compact
    when "experimental"
      @models.values.sample(length)
    when "quality"
      [categories[:image].sample, *categories[:enhance].sample(2),
       categories[:style].sample].compact
    else
      @models.values.sample(length)
    end

    chain.map { |m| { id: m["id"], cost: m["cost"] || 0.05 } }
  end

  private

  def setup_browser
    require "ferrum"
    @browser = Ferrum::Browser.new(headless: true, timeout: 30, window_size: [1920, 1080])
    FileUtils.mkdir_p("discovery_screenshots")
    true
  rescue LoadError
    Bootstrap.dmesg "ERROR ferrum gem required"
    false
  rescue => e
    Bootstrap.dmesg "ERROR browser: #{e.message}"
    false
  end

  def screenshot_page(page_num)
    path = "discovery_screenshots/page_#{page_num}.png"
    @browser.screenshot(path: path, full: true)
    path
  rescue => e
    Bootstrap.dmesg "WARN screenshot: #{e.message}"
    nil
  end

  def extract_via_gpt4v(screenshot, html)
    return nil unless @anthropic_token
    require "base64"

    image_b64 = Base64.strict_encode64(File.read(screenshot))
    uri = URI("https://api.anthropic.com/v1/messages")
    req = Net::HTTP::Post.new(uri)
    req["x-api-key"] = @anthropic_token
    req["anthropic-version"] = "2023-06-01"
    req["Content-Type"] = "application/json"
    req.body = JSON.generate({
      model: "claude-sonnet-4-20250514",
      max_tokens: 2000,
      messages: [{
        role: "user",
        content: [
          { type: "image", source: { type: "base64", media_type: "image/png", data: image_b64 }},
          { type: "text", text: "Extract Replicate models from this screenshot as JSON: [{\"id\":\"owner/name\",\"type\":\"image/video/audio\",\"description\":\"...\",\"cost\":0.05}]. HTML context: #{html[0..3000]}" }
        ]
      }]
    })

    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 90) { |http| http.request(req) }
    return nil unless res.code == "200"

    content = JSON.parse(res.body).dig("content", 0, "text")
    JSON.parse(content.gsub(/```json\n?/, "").gsub(/```/, ""))
  rescue => e
    Bootstrap.dmesg "WARN claude vision: #{e.message}"
    nil
  end

  def next_page
    btn = @browser.at_css('a[rel="next"]') || @browser.at_css('button:contains("Next")')
    return false unless btn
    btn.click
    true
  rescue
    false
  end

  def cleanup
    @browser&.quit
    @browser = nil
  end

  def load_from_db
    return {} unless @db
    @db.results_as_hash = true
    rows = @db.execute("SELECT * FROM models")
    rows.map { |r| [r["id"], r] }.to_h
  rescue
    {}
  end

  def save_model_to_db(model)
    return unless @db
    @db.execute(<<-SQL, [model["id"], model["type"], model["description"], model["cost"] || 0.05, model["documentation"], Time.now.to_i])
      INSERT OR REPLACE INTO models (id, type, description, cost, documentation, discovered_at)
      VALUES (?, ?, ?, ?, ?, ?)
    SQL
  rescue => e
    Bootstrap.dmesg "WARN db save: #{e.message}"
  end
end

  def interactive_cli
    puts "\n" + "="*70
    puts "REPLIGEN 8.0 - CINEMATIC AI PIPELINE"
    puts "Powered by: Kling, Luma, Veo, Hailuo, Flux, Wan"
    puts "="*70
    puts

    puts "📸 Do you have an input image URL? (or press Enter to generate one)"
    print "> "
    input_image = gets.chomp.strip
    input_image = nil if input_image.empty?

    if input_image.nil?
      puts "\n🎨 Describe the image you want to create:"
      print "> "
      prompt = gets.chomp.strip
      prompt = "cinematic masterpiece" if prompt.empty?
      
      puts "\n🖼️  Choose image model:"
      puts "  1. Flux Pro (recommended) - photorealistic, $0.04"
      puts "  2. Flux Schnell - lightning fast, $0.003"
      puts "  3. Imagen4 - Google's latest, $0.015"
      puts "  4. Seedream 4.5 - spatial understanding, $0.03"
      puts "  5. Ideogram - great for text/posters, $0.04"
      print "> "
      img_choice = gets.chomp.strip
      
      img_model = case img_choice
      when '1', '' then :flux_pro
      when '2' then :flux_schnell
      when '3' then :imagen4
      when '4' then :seedream
      when '5' then :ideogram
      else :flux_pro
      end
    else
      prompt = input_image
      img_model = nil
    end

    puts "\n🎬 What type of video do you want?"
    puts "  1. Hollywood (Kling) - best quality, 10s, $0.15"
    puts "  2. Cinematic (Luma Ray2) - smooth motion, 5s, $0.12" 
    puts "  3. Ultra HD (Veo 3.1) - 4K + audio, 8s, $0.20"
    puts "  4. Premium (Sora 2) - OpenAI, synced audio, $0.30"
    puts "  5. Fast (Wan720) - quick & cheap, 5s, $0.06"
    puts "  6. Budget (Hailuo Fast) - good quality, 6s, $0.05"
    puts "  7. Pro (Seedance Pro) - ByteDance, cinematic, $0.15"
    print "> "
    video_choice = gets.chomp.strip

    video_model = case video_choice
    when '1', '' then :kling
    when '2' then :luma
    when '3' then :veo
    when '4' then :sora
    when '5' then :wan720
    when '6' then :hailuo_fast
    when '7' then :seedance_pro
    else :kling
    end

    puts "\n🎵 Add soundtrack?"
    puts "  1. Yes - Cinematic music ($0.02)"
    puts "  2. No"
    print "> "
    music_choice = gets.chomp.strip

    puts "\n⬆️  Apply upscaling?"
    puts "  1. Yes - Topaz Pro ($0.008)"
    puts "  2. Yes - Crystal AI ($0.015)"
    puts "  3. Yes - Clarity AI ($0.01)"
    puts "  4. No"
    print "> "
    upscale_choice = gets.chomp.strip

    # Build pipeline
    chain_steps = []
    chain_steps << img_model if img_model
    
    case upscale_choice
    when '1' then chain_steps << :upscale_topaz
    when '2' then chain_steps << :crystal
    when '3' then chain_steps << :clarity
    end
    
    chain_steps << video_model
    chain_steps << :music if music_choice == '1'

    puts "\n" + "-"*70
    puts "🎯 YOUR CINEMATIC PIPELINE"
    puts "-"*70
    chain_steps.each_with_index do |step, i|
      puts "  #{i+1}. #{step.to_s.upcase}"
    end
    
    estimated_cost = chain_steps.sum { |m| COSTS[m] || 0.05 }
    puts "\n💰 Estimated cost: $#{estimated_cost.round(3)}"
    puts "⏱️  Estimated time: #{chain_steps.length * 30}s"

    print "\n✅ Proceed? (Y/n): "
    response = gets.chomp.downcase
    return unless response.empty? || response.start_with?("y")

    puts "\n🚀 Generating..."
    result = execute_chain(chain_steps, prompt)

    if @postpro && result
      puts "\n" + "="*70
      puts "🎨 POSTPRO.RB CINEMATIC GRADING"
      puts "="*70
      puts "Apply film-grade color grading?"
      puts "• Kodak film curves • Professional grain"
      print "\nLaunch postpro.rb? (Y/n): "

      response = gets.chomp.downcase
      system("ruby postpro.rb --from-repligen") if response.empty? || response.start_with?("y")
    end

    puts "\n✓ Complete! Cinematic masterpiece created."
    puts "\n🔁 Generate another? (y/N): "
    response = gets.chomp.downcase
    interactive_cli if response.start_with?("y")
  end

  def execute_chain(steps, prompt)
    output = prompt
    cost = 0.0
    start_time = Time.now

    steps.each_with_index do |model, i|
      puts "\n" + "─"*70
      puts "⚙️  Step #{i+1}/#{steps.length}: #{model.to_s.upcase}"
      puts "─"*70
      
      step_start = Time.now
      output = predict(model, output)
      step_duration = Time.now - step_start
      
      cost += COSTS[model]
      
      puts "✓ Completed in #{step_duration.round(1)}s (cost: $#{COSTS[model]})"
      
      # Save intermediate results for video models
      if [:kling, :luma, :veo, :wan720, :wan1080, :hailuo, :runway].include?(model)
        save_output(output, model, prompt) if output.is_a?(String) && output.start_with?("http")
      end
    end

    total_duration = Time.now - start_time
    log_chain(steps.map(&:to_s), cost)
    
    puts "\n" + "="*70
    puts "🎉 PIPELINE COMPLETE"
    puts "="*70
    puts "⏱️  Total time: #{total_duration.round(1)}s"
    puts "💰 Total cost: $#{cost.round(3)}"
    puts "="*70
    
    # Save final output
    save_output(output, :final, prompt) if output.is_a?(String) && output.start_with?("http")
    output
  end
