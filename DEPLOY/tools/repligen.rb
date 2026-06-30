#!/usr/bin/env ruby
# frozen_string_literal: true
# Repligen - Replicate.com AI Generation CLI
# Version: 5.0.0 - Consolidated (zero sprawl per master.json)
#
# Usage:
#   ruby repligen.rb              # Interactive menu
#   ruby repligen.rb sync 100     # Sync 100 models
#   ruby repligen.rb search upscale
#   ruby repligen.rb stats

require "net/http"
require "json"
require "fileutils"
require "uri"

# ============================================================================
# CONFIGURATION
# ============================================================================

CONFIG_PATH = File.expand_path("~/.config/repligen/config.json")
DB_PATH = ENV.fetch("REPLIGEN_DB") { File.expand_path("~/.local/share/repligen/repligen.db") }

# Model type patterns (embedded)
MODEL_TYPES = {
  "text-to-image" => ["text.*image", "txt2img", "t2i", "dalle", "stable.*diffusion", "flux", "sdxl", "imagen"],
  "image-to-video" => ["image.*video", "img2vid", "i2v", "animate"],
  "upscale" => ["upscale", "super.*res", "enhance"],
  "image-processing" => ["background", "rembg", "segment", "mask"],
  "style-transfer" => ["style", "artistic"],
  "video" => ["video", "motion"],
  "audio" => ["audio", "music", "sound", "tts", "speech"],
  "3d" => ["3d", "mesh", "model"]
}.freeze

CHAIN_TEMPLATES = {
  "masterpiece" => [
    { type: "text-to-image", count: 1 },
    { types: ["upscale", "style-transfer", "image-processing"], count_range: [3, 8] },
    { types: ["upscale", "image-to-video"], count: 1 }
  ],
  "quick" => [
    { type: "text-to-image", count: 1 },
    { type: "upscale", count: 1 }
  ],
  "chaos" => [
    { types: MODEL_TYPES.keys, count_range: [8, 15] }
  ]
}.freeze

LORA_TRAINER = "ostris/flux-dev-lora-trainer"

# ============================================================================
# BOOTSTRAP
# ============================================================================

def ensure_gems
  require "sqlite3"
rescue LoadError
  abort "[repligen] missing sqlite3 gem. Install dependencies outside repligen before running."
end

# ============================================================================
# ZIPPER (training images -> flat zip, for upload to Replicate)
# ============================================================================

module Zipper
  IMAGE_GLOB = "*.{jpg,jpeg,JPG,JPEG,png,PNG,webp,WEBP}"
  RECOMMENDED_MIN = 12
  RECOMMENDED_MAX = 18

  def self.collect_images(photos_dir)
    Dir.glob(File.join(photos_dir, IMAGE_GLOB))
      .select { |path| File.file?(path) }
      .uniq { |path| File.expand_path(path) }
      .sort
  end

  # Replicate ostris/flux-dev-lora-trainer expects caption filenames, e.g.
  # a_photo_of_TOK.png — not raw camera rolls (1.jpg, IMG_0423.heic).
  def self.captioned_copies(images, trigger_word, staging_dir)
    FileUtils.mkdir_p(staging_dir)
    images.each_with_index.map do |src, index|
      ext = File.extname(src).downcase
      ext = ".jpg" if ext.empty?
      caption = format("a_photo_of_%s_%02d%s", trigger_word, index + 1, ext)
      dest = File.join(staging_dir, caption)
      FileUtils.cp(src, dest)
      dest
    end
  end

  def self.zip(photos_dir, out_path, trigger_word: "subjectxyz")
    ensure_zip_binary
    images = collect_images(photos_dir)
    abort "[repligen] no images found in #{photos_dir}" if images.empty?

    staging_dir = File.join(File.dirname(out_path), "repligen_staging_#{Process.pid}")
    FileUtils.rm_rf(staging_dir)
    captioned = captioned_copies(images, trigger_word, staging_dir)

    File.delete(out_path) if File.exist?(out_path)
    system("zip", "-jq", out_path, *captioned) || abort("[repligen] zip failed")
    FileUtils.rm_rf(staging_dir)
    out_path
  end

  def self.validate(photos_dir, trigger_word: "subjectxyz")
    images = collect_images(photos_dir)
    issues = []
    warnings = []

    issues << "no images in #{photos_dir}" if images.empty?
    warnings << "only #{images.size} images (Replicate recommends #{RECOMMENDED_MIN}-#{RECOMMENDED_MAX} for character LoRAs)" if images.size.positive? && images.size < RECOMMENDED_MIN
    warnings << "#{images.size} images exceeds typical #{RECOMMENDED_MAX}-image sweet spot" if images.size > RECOMMENDED_MAX

    images.each do |path|
      size = File.size(path)
      warnings << "#{File.basename(path)} is only #{size} bytes — may be too small" if size < 20_000
    end

    { images: images, issues: issues, warnings: warnings, trigger_word: trigger_word }
  end

  def self.ensure_zip_binary
    return if system("which zip", out: File::NULL, err: File::NULL)

    abort "[repligen] 'zip' not found. Install: doas pkg_add zip / apt install zip (macOS already has it)."
  end
end

# ============================================================================
# CONFIG MODULE
# ============================================================================

module Config
  def self.token?
    !load_token.to_s.strip.empty?
  rescue StandardError
    false
  end

  def self.load
    token = load_token.to_s.strip
    return token unless token.empty?
    fail_with_instructions
  end

  def self.load_token
    token = ENV["REPLICATE_API_TOKEN"].to_s.strip
    return token unless token.empty?

    # VPS master.env and rc.d use REPLICATE_API_KEY; accept either name.
    token = ENV["REPLICATE_API_KEY"].to_s.strip
    return token unless token.empty?

    return load_from_file if File.exist?(CONFIG_PATH)
    nil
  end

  def self.save(token)
    FileUtils.mkdir_p(File.dirname(CONFIG_PATH))
    File.write(CONFIG_PATH, JSON.pretty_generate({ api_token: token }))
    File.chmod(0600, CONFIG_PATH)
  end

  private

  def self.load_from_file
    token = JSON.parse(File.read(CONFIG_PATH))["api_token"]
    return token if token
    fail_with_instructions
  end

  def self.fail_with_instructions
    abort <<~MSG

      Missing REPLICATE_API_TOKEN

      Get your token: https://replicate.com/account/api-tokens
      Then either:
        export REPLICATE_API_TOKEN=r8_...
      Or:
        echo '{"api_token":"r8_..."}' > #{CONFIG_PATH}
        chmod 600 #{CONFIG_PATH}
    MSG
  end
end

# ============================================================================
# DATABASE MODULE
# ============================================================================

Model = Struct.new(:id, :owner, :name, :description, :type, :cost, :runs, :url, keyword_init: true)

class Database
  attr_reader :db

  def initialize(path = DB_PATH)
    @db = SQLite3::Database.new(path)
    @db.results_as_hash = true
    setup_schema
  end

  def setup_schema
    @db.execute_batch <<-SQL
      CREATE TABLE IF NOT EXISTS models (
        id TEXT PRIMARY KEY,
        owner TEXT NOT NULL,
        name TEXT NOT NULL,
        description TEXT,
        type TEXT,
        cost REAL DEFAULT 0.05,
        runs INTEGER DEFAULT 0,
        url TEXT,
        synced_at INTEGER
      );
      CREATE INDEX IF NOT EXISTS idx_type ON models(type);
      CREATE INDEX IF NOT EXISTS idx_owner ON models(owner);
    SQL
  end

  def save(model)
    @db.execute(<<-SQL, model.values_at(:id, :owner, :name, :description, :type, :cost, :runs, :url))
      INSERT OR REPLACE INTO models (id, owner, name, description, type, cost, runs, url, synced_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, #{Time.now.to_i})
    SQL
  end

  def by_type(type, limit = 100)
    rows = @db.execute("SELECT * FROM models WHERE type = ? ORDER BY RANDOM() LIMIT ?", [type, limit])
    rows.map { |r| Model.new(**r.transform_keys(&:to_sym).slice(*Model.members)) }
  end

  def search(query, limit = 20)
    pattern = "%#{query}%"
    rows = @db.execute(
      "SELECT * FROM models WHERE id LIKE ? OR description LIKE ? ORDER BY runs DESC LIMIT ?",
      [pattern, pattern, limit]
    )
    rows.map { |r| Model.new(**r.transform_keys(&:to_sym).slice(*Model.members)) }
  end

  def random(count = 10)
    rows = @db.execute("SELECT * FROM models ORDER BY RANDOM() LIMIT ?", [count])
    rows.map { |r| Model.new(**r.transform_keys(&:to_sym).slice(*Model.members)) }
  end

  def count
    @db.execute("SELECT COUNT(*) as c FROM models")[0]["c"]
  end

  def stats
    total = count
    by_type = @db.execute("SELECT type, COUNT(*) as count FROM models WHERE type IS NOT NULL GROUP BY type ORDER BY count DESC")
    { total: total, by_type: by_type }
  end
end

# ============================================================================
# API MODULE
# ============================================================================

class API
  BASE = "https://api.replicate.com/v1"

  def initialize(token)
    @token = token
  end

  def models(limit: 1000)
    all_models = []
    cursor = nil

    loop do
      uri = URI("#{BASE}/models")
      uri.query = cursor ? URI.encode_www_form({ cursor: cursor }) : ""
      data = get(uri)
      results = data["results"] || []
      all_models.concat(results)

      next_url = data["next"]
      cursor = next_url ? URI.decode_www_form(URI.parse(next_url).query || "").to_h["cursor"] : nil
      break if cursor.nil? || all_models.size >= limit
    end

    all_models.map { |m| parse_model(m) }
  end

  def predict(model_id, input)
    pred = post(URI("#{BASE}/predictions"), { version: latest_version(model_id), input: input })
    wait_for(pred["id"])
  end

  def model_exists?(model_id)
    owner, name = model_id.split("/")
    get(URI("#{BASE}/models/#{owner}/#{name}"))
    true
  rescue StandardError
    false
  end

  def create_model(model_id, hardware: "cpu")
    owner, name = model_id.split("/")
    post(URI("#{BASE}/models"), { owner: owner, name: name, visibility: "private", hardware: hardware })
  end

  # Uploads a local file (e.g. a training-images zip) and returns its serving URL.
  def upload_zip(path)
    boundary = "RepligenBoundary#{rand(1_000_000_000)}"
    req = Net::HTTP::Post.new(URI("#{BASE}/files"))
    req["Authorization"] = "Token #{@token}"
    req["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
    req.body = multipart_body(path, boundary)
    data = request(req, URI("#{BASE}/files"))
    data.dig("urls", "get") || data["serving_url"] || data["url"] || raise("Upload did not return a URL: #{data}")
  end

  def train_lora(photos_zip_url, destination, trigger_word: "subjectxyz")
    create_model(destination) unless model_exists?(destination)

    trainer_owner, trainer_name = LORA_TRAINER.split("/")
    trainer_version = latest_version(LORA_TRAINER)
    trainings_uri = URI("#{BASE}/models/#{trainer_owner}/#{trainer_name}/versions/#{trainer_version}/trainings")
    training = post(trainings_uri, {
      destination: destination,
      input: { input_images: photos_zip_url, trigger_word: trigger_word }
    })

    wait_for_training(training["id"])
  end

  private

  def latest_version(model_id)
    owner, name = model_id.split("/")
    model = get(URI("#{BASE}/models/#{owner}/#{name}"))
    model.dig("latest_version", "id") || raise("No version for #{model_id}")
  end

  # Hand-rolled multipart body: the file bytes must pass through untouched, so
  # only the ASCII boundary text is forced to binary encoding for concatenation.
  def multipart_body(path, boundary)
    filename = File.basename(path)
    "--#{boundary}\r\n".b +
      "Content-Disposition: form-data; name=\"content\"; filename=\"#{filename}\"\r\n".b +
      "Content-Type: application/zip\r\n\r\n".b +
      File.binread(path) +
      "\r\n--#{boundary}--\r\n".b
  end

  def get(uri)
    req = Net::HTTP::Get.new(uri)
    req["Authorization"] = "Token #{@token}"
    request(req, uri)
  end

  def post(uri, body)
    req = Net::HTTP::Post.new(uri)
    req["Authorization"] = "Token #{@token}"
    req["Content-Type"] = "application/json"
    req.body = body.to_json
    request(req, uri)
  end

  def request(req, uri)
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 120) do |http|
      http.request(req)
    end
    raise "API error #{res.code}: #{res.body}" unless res.code.to_i.between?(200, 299)
    JSON.parse(res.body)
  end

  def wait_for(id, timeout: 600)
    start = Time.now
    loop do
      pred = get(URI("#{BASE}/predictions/#{id}"))
      case pred["status"]
      when "succeeded" then return pred["output"]
      when "failed" then raise "Prediction failed: #{pred['error']}"
      when "canceled" then raise "Canceled"
      end
      raise "Timeout after #{timeout}s" if Time.now - start > timeout
      print "."
      sleep 3
    end
  end

  def wait_for_training(id, timeout: 1800)
    start = Time.now
    loop do
      training = get(URI("#{BASE}/trainings/#{id}"))
      case training["status"]
      when "succeeded" then return training.dig("output", "version") || training["output"]
      when "failed" then raise "Training failed: #{training['error']}"
      when "canceled" then raise "Training canceled"
      end
      raise "Training timeout after #{timeout}s" if Time.now - start > timeout
      print "."
      sleep 5
    end
  end

  def parse_model(data)
    {
      id: "#{data['owner']}/#{data['name']}",
      owner: data["owner"],
      name: data["name"],
      description: data["description"],
      type: infer_type(data["name"], data["description"]),
      cost: 0.05,
      runs: data["run_count"] || 0,
      url: data["url"]
    }
  end

  def infer_type(name, desc)
    combined = "#{name} #{desc}".downcase
    MODEL_TYPES.each do |type, patterns|
      patterns.each do |pattern|
        return type if combined.match?(/#{pattern}/i)
      end
    end
    "other"
  end
end

# ============================================================================
# CHAIN BUILDER
# ============================================================================

Chain = Struct.new(:models, :cost, keyword_init: true)

class ChainBuilder
  def initialize(db, api)
    @db = db
    @api = api
  end

  def build(template_name = "masterpiece")
    template = CHAIN_TEMPLATES[template_name]
    raise "Unknown template: #{template_name}" unless template

    models = []
    cost = 0.0

    template.each do |phase|
      count = if phase[:count_range]
                rand(phase[:count_range][0]..phase[:count_range][1])
              else
                phase[:count]
              end

      count.times do
        # A fixed phase[:type] holds for every step; a phase[:types] pool is
        # re-sampled per step, so a long "chaos" phase varies model by model.
        type = phase[:type] || phase[:types].sample
        candidates = @db.by_type(type, 20)
        next if candidates.empty?

        model = candidates.sample
        models << model
        cost += model.cost
      end
    end

    Chain.new(models: models, cost: cost.round(3))
  end

  def execute(chain, initial_input)
    puts "\n🎬 EXECUTING CHAIN (#{chain.models.size} steps)"
    puts "=" * 70

    output = initial_input
    total_cost = 0.0

    chain.models.each_with_index do |model, i|
      puts "\n[#{i+1}/#{chain.models.size}] #{model.id} (#{model.type})"
      begin
        input = format_input(model.type, output)
        output = @api.predict(model.id, input)
        total_cost += model.cost
        puts "  ✓ $#{model.cost.round(3)}"
        sleep 1 # Rate limit
      rescue StandardError => e
        puts "  ✗ #{e.message}"
        puts "  → Continuing with previous output"
      end
    end

    puts "\n" + "=" * 70
    puts "✓ Complete! Total: $#{total_cost.round(3)}"
    { output: output, cost: total_cost }
  end

  private

  def format_input(type, prev)
    case type
    when "text-to-image"
      { prompt: prev.is_a?(String) ? prev : "masterpiece artwork" }
    when "image-to-video"
      prev.is_a?(String) && prev.start_with?("http") ?
        { image: prev } : { prompt: "cinematic motion" }
    when "upscale"
      prev.is_a?(String) && prev.start_with?("http") ?
        { image: prev, scale: 2 } : { prompt: "enhance" }
    when "image-processing", "style-transfer"
      prev.is_a?(String) && prev.start_with?("http") ?
        { image: prev } : { prompt: "process" }
    else
      prev.is_a?(Hash) ? prev : { input: prev }
    end
  end
end

# ============================================================================
# INTERACTIVE MENU
# ============================================================================

def show_menu
  puts "\n" + "=" * 60
  puts "🎨 REPLIGEN - Replicate.com AI Generation"
  puts "=" * 60
  puts
  puts "1. Sync Models from Replicate"
  puts "2. Search Models"
  puts "3. Generate with LoRA URL"
  puts "4. Run Chain Workflow"
  puts "5. Train LoRA from photos -> chaos chain -> postpro"
  puts "6. Show Statistics"
  puts "7. Exit"
  puts
  print "Choose [1-7]: "
  gets.chomp
end

def interactive_mode
  ensure_gems
  token = Config.load
  api = API.new(token)
  db = Database.new

  loop do
    choice = show_menu

    case choice
    when "1"
      print "How many models to sync? [100]: "
      limit = gets.chomp
      limit = limit.empty? ? 100 : limit.to_i
      sync_models(api, db, limit)

    when "2"
      print "Search query: "
      query = gets.chomp
      results = db.search(query, 20)
      puts "\n📋 Results (#{results.size}):"
      results.each { |m| puts "  #{m.id} - #{m.description&.slice(0, 60)}" }

    when "3"
      print "LoRA model URL (replicate.com/owner/model): "
      url = gets.chomp
      if url =~ /replicate\.com\/([\w-]+\/[\w-]+)/
        model_id = $1
        print "Prompt [masterpiece, best quality]: "
        prompt = gets.chomp
        prompt = "masterpiece, best quality" if prompt.empty?
        generate_with_lora(api, model_id, prompt)
      else
        puts "❌ Invalid URL"
      end

    when "4"
      print "Template [masterpiece/quick/chaos]: "
      template = gets.chomp
      template = "masterpiece" if template.empty?
      run_chain(db, api, template)

    when "5"
      print "Photos directory: "
      photos_dir = gets.chomp
      print "Destination model (owner/name): "
      destination = gets.chomp
      print "Trigger word [subjectxyz]: "
      trigger_word = gets.chomp
      trigger_word = "subjectxyz" if trigger_word.empty?
      if Dir.exist?(photos_dir) && !destination.empty?
        run_lora_chaos(api, db, photos_dir, destination, trigger_word)
      else
        puts "❌ Need a valid photos directory and destination model"
      end

    when "6"
      show_stats(db)

    when "7", "q", "quit", "exit"
      puts "\n👋 Goodbye!"
      exit 0

    else
      puts "\n⚠️  Invalid choice"
    end
  end
end

# ============================================================================
# COMMANDS
# ============================================================================

def sync_models(api, db, limit)
  puts "\n📡 Syncing #{limit} models from Replicate..."
  models = api.models(limit: limit)
  models.each { |m| db.save(m) }
  puts "✓ Synced #{models.size} models"
end

def download_file(url, dir, name = "out")
  FileUtils.mkdir_p(dir)
  ext = File.extname(URI.parse(url).path).sub(/\?.*/, "")
  ext = ".out" if ext.empty?
  filename = File.join(dir, "#{name}#{ext}")
  puts "💾 Downloading #{url}..."
  system("curl", "-s", "-o", filename, url)
  puts "✓ #{filename}"
  filename
end

def generate_with_lora(api, model_id, prompt)
  puts "\n🚀 Generating with #{model_id}..."
  output = api.predict(model_id, { prompt: prompt })
  output_dir = "output/#{model_id.gsub('/', '_')}_#{Time.now.to_i}"

  urls = output.is_a?(Array) ? output : [output].compact
  urls.each_with_index { |url, i| download_file(url, output_dir, "out_#{i}") }

  puts "\n✓ Complete! Output: #{output_dir}"
end

def run_chain(db, api, template)
  builder = ChainBuilder.new(db, api)
  chain = builder.build(template)

  puts "\n🎬 Chain Built (#{chain.models.size} steps, $#{chain.cost})"
  chain.models.each_with_index { |m, i| puts "  #{i+1}. #{m.id} ($#{m.cost})" }

  print "\nExecute? [y/N]: "
  return unless gets.chomp.downcase == "y"

  print "Initial prompt: "
  prompt = gets.chomp
  prompt = "masterpiece artwork" if prompt.empty?

  result = builder.execute(chain, prompt)
  puts "\n✓ Final output: #{result[:output]}"
end

def show_stats(db)
  stats = db.stats
  puts "\n📊 Database Statistics"
  puts "=" * 60
  puts "Total models: #{stats[:total]}"
  puts "\nBy Type:"
  stats[:by_type].each { |row| puts "  #{row['type']&.ljust(20)} #{row['count']}" }
end

POSTPRO_PRESETS = %i[portrait cinematic magic_hour blockbuster golden_age reversal
                     warmth noir masterpiece anamorphic aged_kodachrome].freeze

def run_postpro(input_path, output_path, preset_name)
  postpro = File.expand_path("postpro/postpro.rb", __dir__)
  unless File.exist?(postpro)
    puts "⚠️  postpro.rb not found at #{postpro}, skipping post-processing"
    return input_path
  end

  system("ruby", postpro, "--input", input_path, "--output", output_path, "--preset", preset_name.to_s,
         chdir: File.dirname(postpro))
  File.exist?(output_path) ? output_path : input_path
end

# Train a LoRA on a folder of plain photos, returning a base image URL generated
# from the freshly trained weights.
def print_lora_validation(photos_dir, trigger_word)
  report = Zipper.validate(photos_dir, trigger_word: trigger_word)
  puts "\n📋 LoRA dataset check (#{report[:images].size} images, trigger=#{trigger_word})"
  report[:warnings].each { |w| puts "  ⚠️  #{w}" }
  report[:issues].each { |i| puts "  ❌ #{i}" }
  abort "[repligen] dataset not ready" unless report[:issues].empty?
  report
end

def train_and_generate_base(api, photos_dir, destination, trigger_word)
  print_lora_validation(photos_dir, trigger_word)
  puts "\n📦 Zipping #{photos_dir} (captioned for Replicate)..."
  zip_path = Zipper.zip(photos_dir, "/tmp/repligen_lora_#{Time.now.to_i}.zip", trigger_word: trigger_word)

  puts "☁️  Uploading training images..."
  zip_url = api.upload_zip(zip_path)

  puts "🏋️  Training LoRA -> #{destination} (this can take 10-20 min)..."
  trained_version = api.train_lora(zip_url, destination, trigger_word: trigger_word)
  puts "\n✓ Trained: #{trained_version}"

  puts "\n🚀 Generating base image with the trained LoRA..."
  base_output = api.predict(destination, { prompt: "#{trigger_word}, masterpiece, best quality" })
  base_output.is_a?(Array) ? base_output.first : base_output
end

def download_chain_result(result, base_url, output_dir)
  chained_url = result[:output]
  chained_is_url = chained_url.is_a?(String) && chained_url.start_with?("http")
  return download_file(base_url, output_dir, "base") unless chained_is_url

  download_file(chained_url, output_dir, "chained")
end

# Run a base image through a long randomly-sampled "chaos" chain of other
# Replicate models, then hand the final frame to postpro.rb for film grading.
def chase_and_grade(api, db, base_url)
  puts "\n🎬 Building chaos chain..."
  builder = ChainBuilder.new(db, api)
  chain = builder.build("chaos")
  puts "  #{chain.models.size} steps, est. $#{chain.cost}"
  result = builder.execute(chain, base_url)

  output_dir = "output/lora_chaos_#{Time.now.to_i}"
  chained_file = download_chain_result(result, base_url, output_dir)

  preset_name = POSTPRO_PRESETS.sample
  graded_file = chained_file.sub(/(\.\w+)\z/, "_graded\\1")
  puts "\n🎞️  Post-processing with preset=#{preset_name}..."
  [run_postpro(chained_file, graded_file, preset_name), chain.cost]
end

def run_lora_chaos(api, db, photos_dir, destination, trigger_word)
  base_url = train_and_generate_base(api, photos_dir, destination, trigger_word)
  final_file, chain_cost = chase_and_grade(api, db, base_url)

  puts "\n✓ Complete! Chain cost: $#{chain_cost.round(3)} (+ training cost on your Replicate bill)"
  puts "  Final: #{final_file}"
  final_file
end

# ============================================================================
# CLI
# ============================================================================

if __FILE__ == $PROGRAM_NAME
  case ARGV[0]
  when "sync"
    ensure_gems
    token = Config.load
    api = API.new(token)
    db = Database.new
    limit = ARGV[1]&.to_i || 100
    sync_models(api, db, limit)

  when "search"
    ensure_gems
    db = Database.new
    query = ARGV[1] || ""
    results = db.search(query, 20)
    puts "Results (#{results.size}):"
    results.each { |m| puts "  #{m.id} - #{m.description&.slice(0, 60)}" }

  when "stats"
    ensure_gems
    db = Database.new
    show_stats(db)

  when "generate"
    ensure_gems
    token = Config.load
    api = API.new(token)
    model_id = ARGV[1]
    prompt = (ARGV[2..] || []).join(" ")
    if model_id && !prompt.empty?
      generate_with_lora(api, model_id, prompt)
    else
      puts "Usage: ruby repligen.rb generate <owner/model> <prompt text>"
      puts "Example: ruby repligen.rb generate black-forest-labs/flux-1.1-pro 'cinematic portrait, natural light, kodak portra'"
    end

  when "lora_chaos"
    ensure_gems
    token = Config.load
    api = API.new(token)
    db = Database.new
    photos_dir = ARGV[1]
    destination = ARGV[2]
    trigger_word = ARGV[3] || "subjectxyz"
    if photos_dir && destination
      run_lora_chaos(api, db, photos_dir, destination, trigger_word)
    else
      puts "Usage: ruby repligen.rb lora_chaos <photos_dir> <owner/destination-model> [trigger_word]"
      puts "Example: ruby repligen.rb lora_chaos ./my_photos myuser/my-lora subjectxyz"
    end

  when "validate_lora"
    photos_dir = ARGV[1]
    trigger_word = ARGV[2] || "subjectxyz"
    abort "Usage: ruby repligen.rb validate_lora <photos_dir> [trigger_word]" unless photos_dir

    report = Zipper.validate(photos_dir, trigger_word: trigger_word)
    print_lora_validation(photos_dir, trigger_word)
    zip_path = "/tmp/repligen_validate_#{Time.now.to_i}.zip"
    Zipper.zip(photos_dir, zip_path, trigger_word: trigger_word)
    puts "  ✓ zip dry-run: #{zip_path} (#{File.size(zip_path)} bytes)"
    if Config.token?
      puts "  ✓ REPLICATE token present (#{Config.load_token.length} chars)"
    else
      puts "  ❌ REPLICATE_API_TOKEN / REPLICATE_API_KEY not set — training will fail until configured"
    end
    exit(report[:issues].empty? ? 0 : 1)

  when "--help", "-h"
    puts <<~HELP
      Repligen - Replicate.com AI Generation CLI

      Usage:
        ruby repligen.rb              # Interactive menu
        ruby repligen.rb sync 100     # Sync 100 models
        ruby repligen.rb search upscale
        ruby repligen.rb stats
        ruby repligen.rb generate black-forest-labs/flux-1.1-pro "pro photo prompt here"
        ruby repligen.rb lora_chaos ./my_photos myuser/my-lora subjectxyz
        ruby repligen.rb validate_lora ./my_photos sarah

      Features:
        - Model discovery & database
        - Direct generation (t2i via Replicate Flux/SD etc.)
        - LoRA generation
        - LoRA training from a local photo folder, then a long random "chaos"
          chain across every model type, then postpro.rb film grading (lora_chaos)
        - Chain workflows (masterpiece/quick/chaos)
        - Cost tracking
        - Pair with postpro.rb for filmic photography polish (grain, kodak stocks, cinematic)
    HELP

  else
    interactive_mode
  end
end
