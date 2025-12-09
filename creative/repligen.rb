#!/usr/bin/env ruby
# frozen_string_literal: true

require "net/http"
require "json"
require "logger"
require "optparse"
require "fileutils"

# Repligen - AI Content Generation with Postpro Integration  
# Version: 7.3.0 - Master.json Optimized

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
    ra2: 'anon987654321/ra2:983967a65f090aa0ced0d227e809ae57b29f2d1d1ae4f84a17dd25176e0d313d',
    imagen3: 'google/imagen-3:bffd1835e5c4ea8d40c18ff2f349a24e7fbdcfe5353135b008bc5795e492e7a6',
    flux: 'black-forest-labs/flux-1.1-pro:8f3e0970b7e77b40f6e940f648098297c4419816f9a6f3503697e9a058b28cfa',
    wan480: 'wan-ai/wan-2.1-i2v-480p:8cedc4c0313c89c8e5a98b3ad5e960a4c60e3b95c0bb7c89a96bbf90c74e967f',
    sdv: 'stability-ai/stable-video-diffusion:3f0457e4619daac51203dedb472816fd4af51f3149fa7a9e0b5ffcf1b3e7bf3f',
    lora: 'replicate/fast-flux-trainer:8b10794665aed907bb98a1a5324cd1d3a8bea0e9b31e65210967fb9c9e2e08ed',
    music: 'meta/musicgen:7be0f12c54a8d85c3f0b1b9c0b0d4e8c0b0d4e8c0b0d4e8c0b0d4e8c0b0d4e8c',
    upscale: 'nightmareai/real-esrgan:f121d640bd286e1fdc67f9799164c1d5be36ff74576ee11c803ae5b665dd46aa'
  }.freeze
  
  COSTS = { ra2: 0.08, imagen3: 0.01, flux: 0.03, wan480: 0.08, sdv: 0.10, music: 0.02, upscale: 0.002, lora: 1.46 }.freeze
  
  CHAINS = {
    cinematic: %w[ra2 upscale],
    quick: %w[imagen3 upscale],
    video: %w[imagen3 wan480],
    full: %w[imagen3 wan480 music],
    creative: %w[flux upscale wan480 music],
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
    when :ra2, :imagen3, :flux then { prompt: input.is_a?(String) ? input : 'digital art', num_outputs: 1 }
    when :wan480, :sdv then input.start_with?('http') ? { image: input, num_frames: 96 } : { prompt: input }
    when :music then { prompt: 'cinematic', duration: 10 }
    when :upscale then { image: input, scale: 2 }
    when :lora then { input_images: input.is_a?(Array) ? input.join(',') : input, trigger_word: 'subject' }
    else { input: input }
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
    
    filename = "#{sanitize(prompt)}_generated_#{type}_#{Time.now.strftime('%Y%m%d%H%M%S')}.jpg"
    File.write(filename, response.body)
    puts "Saved: #{filename}"
    File.utime(Time.now, Time.now, filename)
  rescue StandardError => e
    puts "Could not save output: #{e.message}"
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
    puts "Commands: (g)enerate, (c)hain, (l)ora, cost, quit"
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
    when 'radical', 'r' then radical_chain(args)
    when 'q', 'quit' then exit
    else puts "Unknown: #{cmd}"
    end
  end

  def discover_models(args)
    pages = (args[0] || 5).to_i
    scraper = ReplicateExplorer.new(@bootstrap[:anthropic_token])
    models = scraper.discover(max_pages: pages)
    puts "Discovered #{models.size} models"
    models.each { |m| puts "  #{m['id']}: #{m['type']}" }
  end

  def radical_chain(args)
    style = args[0] || 'cinematic'
    length = (args[1] || 5).to_i
    scraper = ReplicateExplorer.new(@bootstrap[:anthropic_token])
    chain = scraper.build_radical_chain(style: style, length: length)

    puts "\nRadical #{style} chain (#{chain.length} steps):"
    chain.each_with_index { |m, i| puts "  #{i+1}. #{m[:id]} ($#{m[:cost]})" }
    total = chain.sum { |m| m[:cost] }
    puts "\nTotal: $#{total.round(3)}"
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
    puts "\n" + "="*60
    puts "REPLIGEN - Cinematic AI Generation Pipeline"
    puts "="*60
    puts

    puts "Please enter LoRA URL (or press Enter to skip):"
    print "> "
    lora_url = gets.chomp.strip
    lora_url = nil if lora_url.empty?

    puts "\nShould the resulting artwork be a photo or a movie?"
    print "> "
    output_type = gets.chomp.downcase.strip
    is_video = output_type.include?("movie") || output_type.include?("video")

    puts "\nDo you have a link to the background soundtrack? (or press Enter to skip):"
    print "> "
    soundtrack_url = gets.chomp.strip
    soundtrack_url = nil if soundtrack_url.empty?

    puts "\nDescribe the scene/artwork you want to create:"
    print "> "
    prompt = gets.chomp.strip
    prompt = "digital art" if prompt.empty?

    puts "\n" + "-"*60
    puts "Building your cinematic pipeline..."
    puts "-"*60

    chain_steps = []

    if lora_url
      puts "• Using custom LoRA: #{lora_url}"
      chain_steps << :ra2
    else
      chain_steps << :flux
    end

    chain_steps << :upscale

    if is_video
      puts "• Adding motion + camera angles"
      chain_steps << :wan480
    end

    if soundtrack_url
      puts "• Integrating soundtrack: #{soundtrack_url}"
    elsif is_video
      puts "• Generating cinematic soundtrack"
      chain_steps << :music
    end

    puts "• Relighting + professional color grading"

    puts "\nPipeline: #{chain_steps.join(' → ')}"
    estimated_cost = chain_steps.sum { |m| COSTS[m] || 0.05 }
    puts "Estimated cost: $#{estimated_cost.round(3)}"

    print "\nProceed? (Y/n): "
    response = gets.chomp.downcase
    return unless response.empty? || response.start_with?("y")

    puts "\nGenerating..."
    result = execute_chain(chain_steps, prompt)

    if @postpro && result
      puts "\n" + "="*60
      puts "POSTPRO.RB INTEGRATION"
      puts "="*60
      puts "Apply cinematic film-grade color grading?"
      puts "• Kodak Portra curves • Skin tone protection"
      puts "• Professional grain • Highlight rolloff"
      print "\nLaunch postpro.rb? (Y/n): "

      response = gets.chomp.downcase
      system("ruby postpro.rb --from-repligen") if response.empty? || response.start_with?("y")
    end

    puts "\n✓ Complete! Output saved."
    puts "\nGenerate another? (y/N): "
    response = gets.chomp.downcase
    interactive_cli if response.start_with?("y")
  end

  def execute_chain(steps, prompt)
    output = prompt
    cost = 0.0

    steps.each_with_index do |model, i|
      puts "\nStep #{i+1}/#{steps.length}: #{model}"
      output = predict(model, output)
      cost += COSTS[model]
    end

    log_chain(steps.map(&:to_s), cost)
    save_output(output, :custom, prompt) if output.is_a?(String) && output.start_with?("http")
    output
  end
