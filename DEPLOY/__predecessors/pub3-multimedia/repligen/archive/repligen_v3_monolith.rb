#!/usr/bin/env ruby
# frozen_string_literal: true

# Repligen - Complete AI Generation Studio
# Scrape → LoRA → Masterpiece with Random Chains

require "net/http"
require "json"

require "sqlite3"

require "optparse"

require "fileutils"

VERSION = "3.0.0"
# ============================================================================
# BOOTSTRAP & SETUP

# ============================================================================

module Bootstrap
  def self.dmesg(msg)

    puts "[repligen] #{msg}"

  end

  def self.ensure_deps
    required = { "sqlite3" => "sqlite3", "ferrum" => "ferrum (optional, for scraping)" }

    required.each do |gem, desc|

      begin

        require gem

        dmesg "OK #{desc}"

      rescue LoadError

        next if gem == "ferrum" # Optional

        dmesg "Installing #{gem}..."

        system("gem install #{gem} --no-document")

        require gem

      end

    end

  end

  def self.ensure_token
    return ENV["REPLICATE_API_TOKEN"] if ENV["REPLICATE_API_TOKEN"]

    config_file = File.expand_path("~/.config/repligen/config.json")
    if File.exist?(config_file)

      token = JSON.parse(File.read(config_file))["api_token"]

      return ENV["REPLICATE_API_TOKEN"] = token if token

    end

    if $stdin.tty?
      dmesg "Enter REPLICATE_API_TOKEN:"

      print "> "

      token = gets.chomp.strip

      FileUtils.mkdir_p(File.dirname(config_file))
      File.write(config_file, JSON.pretty_generate({ "api_token" => token }))

      File.chmod(0600, config_file)

      ENV["REPLICATE_API_TOKEN"] = token

    else

      dmesg "ERROR: No REPLICATE_API_TOKEN"

      exit 1

    end

  end

end

# ============================================================================
# DATABASE & SCRAPING

# ============================================================================

class ModelDatabase
  attr_reader :db

  def initialize(path = "repligen.db")
    @db = SQLite3::Database.new(path)

    @db.results_as_hash = true

    setup_schema

  end

  def setup_schema
    @db.execute_batch <<-SQL

      CREATE TABLE IF NOT EXISTS models (

        id TEXT PRIMARY KEY,

        owner TEXT,

        name TEXT,

        description TEXT,

        type TEXT,

        version TEXT,

        input_schema TEXT,

        output_schema TEXT,

        cost REAL,

        runs INTEGER,

        url TEXT,

        scraped_at INTEGER

      );

      CREATE INDEX IF NOT EXISTS idx_type ON models(type);
      CREATE INDEX IF NOT EXISTS idx_owner ON models(owner);

      CREATE INDEX IF NOT EXISTS idx_cost ON models(cost);

      CREATE TABLE IF NOT EXISTS chains (
        id INTEGER PRIMARY KEY AUTOINCREMENT,

        models TEXT,

        cost REAL,

        created_at INTEGER

      );

    SQL

  end

  def scrape_explore(max_scrolls = 50)
    Bootstrap.dmesg "Scraping replicate.com/explore (#{max_scrolls} pages)..."

    begin
      require "ferrum"

    rescue LoadError

      Bootstrap.dmesg "ERROR: gem install ferrum required for scraping"

      return 0

    end

    browser = Ferrum::Browser.new(headless: true, timeout: 60, window_size: [1920, 1080])
    discovered = 0

    begin
      browser.goto("https://replicate.com/explore")

      sleep 3

      max_scrolls.times do |i|
        browser.execute("window.scrollTo(0, document.body.scrollHeight)")

        sleep 2

        html = browser.body
        models = extract_models_from_html(html)

        models.each do |model|
          begin

            save_model(model)

            discovered += 1

          rescue SQLite3::ConstraintException

            # Duplicate, skip

          end

        end

        print "\r[#{i+1}/#{max_scrolls}] Scraped: #{discovered} models"
        # Check if reached end
        h1 = browser.evaluate("document.body.scrollHeight")

        browser.execute("window.scrollTo(0, document.body.scrollHeight)")

        sleep 1

        h2 = browser.evaluate("document.body.scrollHeight")

        break if h1 == h2

      end

      puts "\n✓ Scraped #{discovered} models"
      discovered

    ensure

      browser&.quit

    end

  end

  def scrape_model_details(model_id)
    # Fetch detailed model info from Replicate API

    uri = URI("https://api.replicate.com/v1/models/#{model_id}")

    req = Net::HTTP::Get.new(uri)

    req["Authorization"] = "Token #{ENV['REPLICATE_API_TOKEN']}"

    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 30) { |http| http.request(req) }
    return nil unless res.code == "200"

    data = JSON.parse(res.body)
    {
      id: data["owner"] + "/" + data["name"],

      owner: data["owner"],

      name: data["name"],

      description: data["description"],

      version: data.dig("latest_version", "id"),

      input_schema: data.dig("latest_version", "openapi_schema", "components", "schemas", "Input")&.to_json,

      output_schema: data.dig("latest_version", "openapi_schema", "components", "schemas", "Output")&.to_json,

      url: data["url"],

      runs: data["run_count"] || 0,

      cost: estimate_cost_from_schema(data)

    }

  rescue => e

    Bootstrap.dmesg "WARN: Failed to fetch #{model_id}: #{e.message}"

    nil

  end

  def extract_models_from_html(html)
    models = []

    html.scan(/\/([^\/\s"]+)\/([^\/\s"]+)(?!\/[^\/\s"]+)/) do |owner, name|
      next if owner.length < 3 || name.length < 3

      next if owner =~ /^(explore|models|docs|api|blog|pricing|about|terms)$/

      next if name =~ /\.(png|jpg|svg|css|js)$/

      id = "#{owner}/#{name}"
      desc = extract_description(html, id)

      models << {
        id: id,

        owner: owner,

        name: name,

        description: desc,

        type: infer_type(name, desc),

        cost: 0.05,

        runs: 0,

        url: "https://replicate.com/#{id}",

        scraped_at: Time.now.to_i

      }

    end

    models.uniq { |m| m[:id] }
  end

  def extract_description(html, model_id)
    if match = html.match(/#{Regexp.escape(model_id)}.*?<p[^>]*>(.*?)<\/p>/m)

      match[1].gsub(/<[^>]+>/, '').strip[0..300]

    else

      ""

    end

  end

  def infer_type(name, desc)
    combined = "#{name} #{desc}".downcase

    case combined
    when /text.*image|txt2img|t2i|dalle|stable.*diffusion|flux|sdxl|imagen/ then 'text-to-image'

    when /image.*video|img2vid|i2v|animate/ then 'image-to-video'

    when /video|motion/ then 'video'

    when /audio|music|sound|tts|speech/ then 'audio'

    when /upscale|super.*res|enhance/ then 'upscale'

    when /background|rembg|segment|mask/ then 'image-processing'

    when /style|artistic/ then 'style-transfer'

    when /face|portrait|headshot/ then 'face'

    when /lora|train|fine.*tun/ then 'training'

    when /3d|mesh|model/ then '3d'

    when /text|llm|language/ then 'text'

    else 'other'

    end

  end

  def estimate_cost_from_schema(data)
    # Estimate based on model type and complexity

    name = data["name"].to_s.downcase

    return 0.01 if name.include?("fast") || name.include?("turbo")

    return 0.15 if name.include?("pro") || name.include?("ultra")

    0.05 # Default

  end

  def save_model(model)
    @db.execute(<<-SQL, model.values_at(:id, :owner, :name, :description, :type, :version, :input_schema, :output_schema, :cost, :runs, :url, :scraped_at))

      INSERT OR REPLACE INTO models

      (id, owner, name, description, type, version, input_schema, output_schema, cost, runs, url, scraped_at)

      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)

    SQL

  end

  def get_models_by_type(type, limit = 100)
    @db.execute("SELECT * FROM models WHERE type = ? ORDER BY RANDOM() LIMIT ?", [type, limit])

  end

  def get_random_models(count = 10)
    @db.execute("SELECT * FROM models ORDER BY RANDOM() LIMIT ?", [count])

  end

  def search_models(query, limit = 20)
    @db.execute(

      "SELECT * FROM models WHERE id LIKE ? OR description LIKE ? ORDER BY runs DESC LIMIT ?",

      ["%#{query}%", "%#{query}%", limit]

    )

  end

  def count_models
    @db.execute("SELECT COUNT(*) as count FROM models")[0]["count"]

  end

  def stats
    total = count_models

    by_type = @db.execute(

      "SELECT type, COUNT(*) as count FROM models WHERE type IS NOT NULL GROUP BY type ORDER BY count DESC"

    )

    { total: total, by_type: by_type }
  end

end

# ============================================================================
# REPLICATE API CLIENT

# ============================================================================

class ReplicateClient
  API = "https://api.replicate.com/v1"

  def initialize(token)
    @token = token

  end

  def predict(model_id, version, input)
    pred = request("predictions", :post, {

      version: version,

      input: input

    })

    wait_for(pred["id"])
  end

  def predict_by_id(model_id, input)
    # Lookup version from database or fetch from API

    owner, name = model_id.split("/")

    model_data = request("models/#{owner}/#{name}")
    version = model_data.dig("latest_version", "id")

    raise "No version found for #{model_id}" unless version
    predict(model_id, version, input)
  end

  def train_lora(images, trigger_word = "subject")
    raise "Provide at least 5 images" if images.size < 5

    Bootstrap.dmesg "Training LoRA with #{images.size} images..."
    pred = request("predictions", :post, {
      version: "ostris/flux-dev-lora-trainer", # Using popular LoRA trainer

      input: {

        steps: 1000,

        lora_rank: 16,

        optimizer: "adamw8bit",

        batch_size: 1,

        resolution: "512,768,1024",

        autocaption: true,

        trigger_word: trigger_word,

        input_images: images.join(","),

        learning_rate: 0.0004

      }

    })

    result = wait_for(pred["id"], timeout: 1800) # 30 min timeout
    Bootstrap.dmesg "✓ LoRA trained: #{result}"

    result

  end

  private
  def request(endpoint, method = :get, body = nil)
    uri = URI("#{API}/#{endpoint}")

    req = method == :post ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)

    req["Authorization"] = "Token #{@token}"

    req["Content-Type"] = "application/json"

    req.body = body.to_json if body

    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 300) { |http| http.request(req) }
    raise "API Error #{res.code}: #{res.body}" unless res.code.to_i.between?(200, 299)

    JSON.parse(res.body)
  end

  def wait_for(id, timeout: 600)
    start = Time.now

    loop do
      pred = request("predictions/#{id}")

      case pred["status"]
      when "succeeded" then return pred["output"]

      when "failed" then raise "Prediction failed: #{pred['error']}"

      when "canceled" then raise "Prediction canceled"

      end

      raise "Timeout after #{timeout}s" if Time.now - start > timeout
      print "."
      sleep 3

    end

  end

end

# ============================================================================
# CHAIN BUILDER

# ============================================================================

class ChainBuilder
  def initialize(db, client)

    @db = db

    @client = client

  end

  def build_masterpiece_chain(style: :random, length: nil)
    # Build a crazy random chain from scraped models

    length ||= rand(8..20)

    Bootstrap.dmesg "Building #{style} masterpiece chain (#{length} steps)..."
    chain = []
    cost = 0.0

    # Phase 1: Generation (text-to-image)
    gen_models = @db.get_models_by_type("text-to-image", 20)

    if gen_models.any?

      model = gen_models.sample

      chain << model

      cost += model["cost"] || 0.05

    end

    # Phase 2: Enhancement (mix of types)
    (length - 2).times do

      type = [:upscale, :style, :process, :video, :audio].sample

      models = case type
      when :upscale then @db.get_models_by_type("upscale", 10)

      when :style then @db.get_models_by_type("style-transfer", 10)

      when :process then @db.get_models_by_type("image-processing", 10)

      when :video then @db.get_models_by_type("image-to-video", 10)

      when :audio then @db.get_models_by_type("audio", 10)

      end

      if models&.any?
        model = models.sample

        chain << model

        cost += model["cost"] || 0.05

      end

    end

    # Phase 3: Final polish (upscale or video)
    final_type = [:upscale, "image-to-video"].sample

    final_models = @db.get_models_by_type(final_type, 10)

    if final_models.any?

      model = final_models.sample

      chain << model

      cost += model["cost"] || 0.05

    end

    { chain: chain, cost: cost.round(3) }
  end

  def execute_chain(chain, initial_input)
    Bootstrap.dmesg "\n🎬 EXECUTING MASTERPIECE CHAIN"

    Bootstrap.dmesg "=" * 70

    output = initial_input
    total_cost = 0.0

    chain.each_with_index do |model, i|
      puts "\n[#{i+1}/#{chain.size}] #{model['id']} (#{model['type']})"

      puts "  #{model['description']&.slice(0, 80)}"

      begin
        input = format_input(model, output)

        output = @client.predict_by_id(model["id"], input)

        cost = model["cost"] || 0.05
        total_cost += cost

        puts "  ✓ Cost: $#{cost.round(3)}"

        sleep 1 # Rate limiting
      rescue => e

        puts "  ✗ Failed: #{e.message}"

        puts "  → Skipping and continuing with previous output"

      end

    end

    Bootstrap.dmesg "\n" + "=" * 70
    Bootstrap.dmesg "✓ Chain complete! Total cost: $#{total_cost.round(3)}"

    { output: output, cost: total_cost }
  end

  private
  def format_input(model, previous_output)
    type = model["type"]

    case type
    when "text-to-image"

      { prompt: previous_output.is_a?(String) ? previous_output : "masterpiece artwork" }

    when "image-to-video"

      previous_output.is_a?(String) && previous_output.start_with?("http") ?

        { image: previous_output } : { prompt: "cinematic motion" }

    when "upscale"

      previous_output.is_a?(String) && previous_output.start_with?("http") ?

        { image: previous_output, scale: 2 } : { prompt: "enhance" }

    when "audio", "music"

      { prompt: "cinematic score", duration: 10 }

    when "image-processing"

      previous_output.is_a?(String) && previous_output.start_with?("http") ?

        { image: previous_output } : { prompt: "process" }

    else

      previous_output.is_a?(Hash) ? previous_output : { input: previous_output }

    end

  end

end

# ============================================================================
# INTERACTIVE CLI

# ============================================================================

class InteractiveCLI
  def initialize(db, client, builder)

    @db = db

    @client = client

    @builder = builder

    @lora_url = nil

  end

  def run
    show_welcome

    show_current_stats

    loop do
      print "\nrepligen> "

      input = gets&.chomp&.strip

      break if input.nil? || input.empty? || %w[quit exit q].include?(input.downcase)

      handle_input(input)
    rescue Interrupt

      puts "\nBye! 👋"

      break

    rescue => e

      puts "❌ Error: #{e.message}"

      puts e.backtrace.first(3) if ENV["DEBUG"]

    end

  end

  def show_current_stats
    stats = @db.stats

    total = stats[:total]

    if total > 0
      puts "\n📊 Current Database:"

      puts "   Models: #{format_num(total)}"

      puts "   Types: #{stats[:by_type].size} categories"

      puts "   Top: #{stats[:by_type].first(3).map { |t| t['type'] }.join(', ')}"

    else

      puts "\n📊 Database empty - run 'scrape' to populate"

    end

  end

  private
  def show_welcome
    stats = @db.stats

    puts <<~WELCOME
      ╔═══════════════════════════════════════════════════════════════╗
      ║               REPLIGEN v#{VERSION} - All-in-One                 ║

      ║         Scrape → LoRA → Random Masterpiece Chains            ║

      ╚═══════════════════════════════════════════════════════════════╝

      📊 Models in DB: #{format_num(stats[:total])}
      🎨 Types: #{stats[:by_type].size}

      🤖 LoRA: #{@lora_url ? 'Trained ✓' : 'Not trained'}

      Commands:
        scrape [pages]           - Scrape Replicate.com models (interactive if no args)

        lora <image urls...>     - Train LoRA from images (interactive if no args)

        masterpiece <prompt>     - Create with random chain (8-20 steps)

        chain [length] [prompt]  - Custom length chain (interactive if no args)

        search <query>           - Search models

        stats                    - Database statistics

        help                     - Show all commands

      Interactive Mode (press Enter for defaults):
        repligen> scrape         → Pages to scrape [50]:

        repligen> lora           → Number of images [5]:

        repligen> chain          → Chain length [12]:

      Direct Mode:
        repligen> scrape 100

        repligen> lora https://img1.jpg https://img2.jpg https://img3.jpg

        repligen> masterpiece portrait of a cyberpunk warrior

        repligen> chain 15 epic mountain landscape

    WELCOME
  end

  def handle_input(input)
    parts = input.split

    command = parts.shift&.downcase

    case command
    when "scrape"

      if parts.empty?

        print "Pages to scrape [50]: "

        pages_input = gets&.chomp&.strip

        pages = pages_input.empty? ? 50 : pages_input.to_i

      else

        pages = parts.first.to_i

      end

      puts "✓ Scraping #{pages} pages..."
      count = @db.scrape_explore(pages)

      puts "✓ Scraped #{count} models. Total: #{@db.count_models}"

    when "lora"
      if parts.empty?

        puts "\n🎨 LoRA Training Setup"

        print "Number of images [5]: "

        num_images = gets&.chomp&.strip

        num_images = num_images.empty? ? 5 : num_images.to_i

        images = []
        num_images.times do |i|

          print "Image URL #{i+1}: "

          url = gets&.chomp&.strip

          images << url unless url.empty?

        end

        print "Trigger word [subject]: "
        trigger = gets&.chomp&.strip

        trigger = trigger.empty? ? "subject" : trigger

        if images.size < 5
          puts "❌ Need at least 5 images for LoRA training"

          return

        end

        @lora_url = @client.train_lora(images, trigger)
      else

        @lora_url = @client.train_lora(parts[0..-1], "subject")

      end

      puts "✓ LoRA trained: #{@lora_url}"
    when "masterpiece"
      prompt = parts.join(" ")

      create_masterpiece(prompt.empty? ? "stunning artwork" : prompt)

    when "chain"
      if parts.empty?

        print "Chain length [12]: "

        length_input = gets&.chomp&.strip

        length = length_input.empty? ? 12 : length_input.to_i

        print "Prompt [stunning artwork]: "
        prompt_input = gets&.chomp&.strip

        prompt = prompt_input.empty? ? "stunning artwork" : prompt_input

      else

        length = parts.shift&.to_i || 12

        prompt = parts.join(" ")

        prompt = "stunning artwork" if prompt.empty?

      end

      create_masterpiece(prompt, length: length)
    when "search"
      query = parts.join(" ")

      results = @db.search_models(query, 10)

      if results.empty?
        puts "No models found for: #{query}"

      else

        puts "\nFound #{results.size} models:"

        results.each { |m| puts "  • #{m['id']} (#{m['type']}) - #{m['description']&.slice(0, 60)}" }

      end

    when "stats"
      show_stats

    when "help"
      show_help

    else
      # Treat as prompt

      create_masterpiece(input)

    end

  end

  def create_masterpiece(prompt, length: nil)
    if @db.count_models < 10

      puts "⚠️  Database has few models. Run: scrape 50"

      return

    end

    result = @builder.build_masterpiece_chain(length: length)
    chain = result[:chain]

    puts "\n🎨 MASTERPIECE CHAIN (#{chain.size} steps)"
    puts "=" * 70

    chain.each_with_index do |model, i|

      puts "#{i+1}. #{model['id'].ljust(40)} $#{model['cost'] || 0.05}"

    end

    puts "\nTotal cost: $#{result[:cost]}"

    puts "=" * 70

    print "\nExecute chain? [Y/n]: "
    response = gets&.chomp&.downcase

    return unless response.empty? || response.start_with?("y")

    # Use LoRA for first step if available
    initial_input = @lora_url ?

      { prompt: prompt, lora: @lora_url } :

      prompt

    output = @builder.execute_chain(chain, initial_input)
    # Save output
    if output[:output].is_a?(String) && output[:output].start_with?("http")

      filename = "masterpiece_#{Time.now.to_i}.mp4"

      download_file(output[:output], filename)

      puts "\n💾 Saved: #{filename}"

    end

    # Log to database
    @db.db.execute(

      "INSERT INTO chains (models, cost, created_at) VALUES (?, ?, ?)",

      [chain.map { |m| m['id'] }.join(","), output[:cost], Time.now.to_i]

    )

  end

  def download_file(url, destination)
    uri = URI(url)

    response = Net::HTTP.get_response(uri)

    File.write(destination, response.body) if response.code == "200"

  rescue => e

    Bootstrap.dmesg "Download failed: #{e.message}"

  end

  def show_stats
    stats = @db.stats

    puts "\n📊 DATABASE STATISTICS"
    puts "=" * 70

    puts "Total models: #{format_num(stats[:total])}"

    puts "\nBy Category:"

    stats[:by_type].first(15).each do |row|

      puts "  #{row['type'].ljust(25)} #{format_num(row['count']).rjust(8)}"

    end

    # Chain stats
    chains = @db.db.execute("SELECT COUNT(*) as count, SUM(cost) as total_cost FROM chains")

    if chains.any? && chains[0]["count"] > 0

      puts "\nGeneration Stats:"

      puts "  Total chains: #{chains[0]['count']}"

      puts "  Total spent: $#{chains[0]['total_cost']&.round(2)}"

    end

  end

  def show_help
    puts <<~HELP

      📚 REPLIGEN COMMANDS
      Scraping:
        scrape [pages]              Scrape Replicate.com (interactive if no args)

                                    Default: 50 pages

      LoRA Training:
        lora <urls...>              Train LoRA from images (interactive if no args)

                                    Default: 5 images, trigger word "subject"

                                    Min: 5 images required

      Generation:
        masterpiece <prompt>        Random chain (8-20 steps) with all effects

        chain [length] [prompt]     Custom length chain (interactive if no args)

                                    Default: 12 steps, "stunning artwork" prompt

        <any text>                  Direct prompt → masterpiece

      Database:
        search <query>              Search models by keyword

        stats                       Show database statistics

      Interactive Examples (press Enter for defaults):
        repligen> scrape

        Pages to scrape [50]: ← press Enter

        repligen> chain
        Chain length [12]: 15

        Prompt [stunning artwork]: epic mountain landscape

      Direct Examples:
        scrape 100

        lora https://photo1.jpg https://photo2.jpg https://photo3.jpg

        masterpiece cyberpunk portrait with neon lights

        chain 25 epic fantasy landscape

        stats

    HELP
  end

  def format_num(num)
    num.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse

  end

end

# ============================================================================
# MAIN ENTRY POINT

# ============================================================================

if __FILE__ == $0
  Bootstrap.ensure_deps

  token = Bootstrap.ensure_token

  # Parse options
  options = {}

  OptionParser.new do |opts|

    opts.banner = "Usage: repligen.rb [options]"

    opts.on("--scrape [PAGES]", Integer, "Scrape models") { |p| options[:scrape] = p || 50 }

    opts.on("--stats", "Show statistics") { options[:stats] = true }

    opts.on("-h", "--help", "Show help") { puts opts; exit }

  end.parse!

  # Initialize
  db = ModelDatabase.new

  client = ReplicateClient.new(token)

  builder = ChainBuilder.new(db, client)

  # Handle CLI options
  if options[:scrape]

    db.scrape_explore(options[:scrape])

    exit

  elsif options[:stats]

    stats = db.stats

    puts "Models: #{stats[:total]}"

    puts "\nBy type:"

    stats[:by_type].each { |r| puts "  #{r['type']}: #{r['count']}" }

    exit

  end

  # Interactive mode
  cli = InteractiveCLI.new(db, client, builder)

  cli.run

end

