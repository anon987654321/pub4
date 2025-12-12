#!/usr/bin/env ruby
# frozen_string_literal: true

require "net/http"
require "json"
require "sqlite3"
require "fileutils"

# Repligen Model Indexer
# Indexes all Replicate models for random chain generation

class ModelIndexer
  attr_reader :token, :db

  def initialize
    @token = ENV["REPLICATE_API_TOKEN"]
    unless @token
      puts "Error: Set REPLICATE_API_TOKEN"
      exit 1
    end
    
    @db = SQLite3::Database.new("repligen_models.db")
    setup_database
  end

  def setup_database
    @db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS models (
        id TEXT PRIMARY KEY,
        owner TEXT,
        name TEXT,
        description TEXT,
        visibility TEXT,
        run_count INTEGER,
        cost_per_run REAL,
        category TEXT,
        input_schema TEXT,
        output_schema TEXT,
        indexed_at INTEGER
      )
    SQL

    @db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS collections (
        slug TEXT PRIMARY KEY,
        name TEXT,
        description TEXT,
        model_count INTEGER,
        indexed_at INTEGER
      )
    SQL

    @db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS model_collections (
        model_id TEXT,
        collection_slug TEXT,
        PRIMARY KEY (model_id, collection_slug)
      )
    SQL

    puts "✓ Database initialized"
  end

  def api_request(method, path)
    uri = URI("https://api.replicate.com/v1#{path}")
    req = case method
          when :get then Net::HTTP::Get.new(uri)
          end
    
    req["Authorization"] = "Token #{@token}"
    
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
    
    if res.code == "200"
      JSON.parse(res.body)
    else
      puts "API Error: #{res.code} #{res.message}"
      nil
    end
  end

  def index_collections
    puts "\n=== INDEXING COLLECTIONS ==="
    
    collections = []
    cursor = nil
    
    loop do
      path = cursor ? "/collections?cursor=#{cursor}" : "/collections"
      data = api_request(:get, path)
      break unless data
      
      results = data["results"] || []
      collections.concat(results)
      
      puts "  Fetched #{results.size} collections (total: #{collections.size})"
      
      cursor = data["next"]
      break unless cursor
      
      sleep 1 # Rate limiting
    end
    
    # Save to database
    collections.each do |coll|
      @db.execute(
        "INSERT OR REPLACE INTO collections VALUES (?, ?, ?, ?, ?)",
        [coll["slug"], coll["name"], coll["description"], 0, Time.now.to_i]
      )
    end
    
    puts "✓ Indexed #{collections.size} collections"
    collections
  end

  def index_models_for_collection(collection_slug)
    puts "\n  Indexing models in #{collection_slug}..."
    
    path = "/collections/#{collection_slug}"
    data = api_request(:get, path)
    return 0 unless data
    
    models = data["models"] || []
    
    models.each do |model|
      model_id = "#{model["owner"]}/#{model["name"]}"
      
      @db.execute(
        "INSERT OR REPLACE INTO models VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [
          model_id,
          model["owner"],
          model["name"],
          model["description"],
          model["visibility"],
          model["run_count"] || 0,
          0.0, # Will estimate later
          collection_slug,
          nil, # Will fetch schema later
          nil,
          Time.now.to_i
        ]
      )
      
      @db.execute(
        "INSERT OR IGNORE INTO model_collections VALUES (?, ?)",
        [model_id, collection_slug]
      )
    end
    
    # Update collection model count
    @db.execute(
      "UPDATE collections SET model_count = ? WHERE slug = ?",
      [models.size, collection_slug]
    )
    
    puts "    ✓ Indexed #{models.size} models"
    models.size
  end

  def index_all
    puts "\n╔═══════════════════════════════════════════════════════════╗"
    puts "║     REPLIGEN MODEL INDEXER                                ║"
    puts "╚═══════════════════════════════════════════════════════════╝"
    
    start_time = Time.now
    
    # Step 1: Index collections
    collections = index_collections
    
    # Step 2: Index models in each collection
    total_models = 0
    collections.each_with_index do |coll, idx|
      puts "\n[#{idx + 1}/#{collections.size}] #{coll["name"]}"
      count = index_models_for_collection(coll["slug"])
      total_models += count
      sleep 1 # Rate limiting
    end
    
    duration = Time.now - start_time
    
    puts "\n" + "="*70
    puts "🎉 INDEXING COMPLETE!"
    puts "="*70
    puts "Collections: #{collections.size}"
    puts "Models: #{total_models}"
    puts "Duration: #{duration.round(1)}s"
    puts "Database: repligen_models.db"
    puts "="*70
  end

  def stats
    collections_count = @db.execute("SELECT COUNT(*) FROM collections")[0][0]
    models_count = @db.execute("SELECT COUNT(*) FROM models")[0][0]
    
    puts "\n=== DATABASE STATS ==="
    puts "Collections: #{collections_count}"
    puts "Models: #{models_count}"
    
    puts "\nTop 10 Collections by Model Count:"
    @db.execute("SELECT name, model_count FROM collections ORDER BY model_count DESC LIMIT 10").each do |row|
      puts "  #{row[0]}: #{row[1]} models"
    end
    
    puts "\nTop 10 Most Popular Models:"
    @db.execute("SELECT id, run_count FROM models ORDER BY run_count DESC LIMIT 10").each do |row|
      puts "  #{row[0]}: #{row[1]} runs"
    end
  end

  def search_models(query)
    puts "\n=== SEARCHING: #{query} ==="
    
    results = @db.execute(
      "SELECT id, description, category FROM models WHERE id LIKE ? OR description LIKE ? LIMIT 20",
      ["%#{query}%", "%#{query}%"]
    )
    
    if results.empty?
      puts "No results found"
    else
      results.each do |row|
        puts "  #{row[0]}"
        puts "    #{row[1][0..80]}..." if row[1]
        puts "    Category: #{row[2]}"
        puts
      end
    end
  end
end

if __FILE__ == $0
  indexer = ModelIndexer.new
  
  command = ARGV[0] || "index"
  
  case command
  when "index"
    indexer.index_all
  when "stats"
    indexer.stats
  when "search"
    query = ARGV[1] || ""
    indexer.search_models(query)
  else
    puts "Usage: ruby model_indexer.rb [index|stats|search]"
  end
end
