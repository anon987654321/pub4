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
# ============================================================================
# CONFIGURATION

# ============================================================================
CONFIG_PATH = File.expand_path("~/.config/repligen/config.json")
DB_PATH = File.expand_path("repligen.db", __dir__)

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
  ]
}.freeze
# ============================================================================
# BOOTSTRAP

# ============================================================================
def ensure_gems
  begin

    require "sqlite3"
  rescue LoadError
    puts "[repligen] Installing sqlite3..."
    system("gem install sqlite3 --no-document")
    require "sqlite3"
  end
  tty_available = begin
    require "tty-prompt"

    true
  rescue LoadError
    puts "[repligen] tty-prompt not available, using basic prompts"
    false
  end
  tty_available
end
# ============================================================================
# CONFIG MODULE

# ============================================================================
module Config
  def self.load

    return ENV["REPLICATE_API_TOKEN"] if ENV["REPLICATE_API_TOKEN"]
    return load_from_file if File.exist?(CONFIG_PATH)
    fail_with_instructions
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
    owner, name = model_id.split("/")

    model = get(URI("#{BASE}/models/#{owner}/#{name}"))
    version = model.dig("latest_version", "id")
    raise "No version for #{model_id}" unless version
    pred = post(URI("#{BASE}/predictions"), {
      version: version,

      input: input
    })
    wait_for(pred["id"])
  end

  private
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
      type = phase[:type] || phase[:types]&.sample

      count = if phase[:count_range]
                rand(phase[:count_range][0]..phase[:count_range][1])
              else
                phase[:count]
              end
      count.times do
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
      rescue => e
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
  puts "5. Show Statistics"
  puts "6. Exit"
  puts
  print "Choose [1-6]: "
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
      print "Template [masterpiece/quick]: "

      template = gets.chomp
      template = "masterpiece" if template.empty?
      run_chain(db, api, template)
    when "5"
      show_stats(db)

    when "6", "q", "quit", "exit"
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
def generate_with_lora(api, model_id, prompt)
  puts "\n🚀 Generating with #{model_id}..."

  output = api.predict(model_id, { prompt: prompt })
  output_dir = "output/#{model_id.gsub('/', '_')}_#{Time.now.to_i}"
  FileUtils.mkdir_p(output_dir)
  if output.is_a?(Array)
    output.each_with_index do |url, i|

      filename = File.join(output_dir, "image_#{i}.png")
      puts "💾 Downloading #{url}..."
      system("curl -s -o '#{filename}' '#{url}'")
      puts "✓ #{filename}"
    end
  elsif output.is_a?(String)
    filename = File.join(output_dir, "output.png")
    puts "💾 Downloading #{output}..."
    system("curl -s -o '#{filename}' '#{output}'")
    puts "✓ #{filename}"
  end
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
  when "--help", "-h"
    puts <<~HELP

      Repligen - Replicate.com AI Generation CLI
      Usage:
        ruby repligen.rb              # Interactive menu

        ruby repligen.rb sync 100     # Sync 100 models
        ruby repligen.rb search upscale
        ruby repligen.rb stats
      Features:
        - Model discovery & database

        - LoRA generation
        - Chain workflows (masterpiece/quick)
        - Cost tracking
    HELP
  else
    interactive_mode

  end
end
