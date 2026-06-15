#!/usr/bin/env ruby33
# frozen_string_literal: true

# Repligen v2.0 - Enhanced Interactive CLI with NLU
# Natural Language Understanding powered by Claude/Grok/GPT

require_relative "repligen_nlu"
require "json"

class RepligenV2
  def initialize

    @nlu_enabled = setup_nlu

    @db_path = "repligen_models.db"

    setup_welcome

  end

  def setup_nlu
    @vector_store = RepligenNLU::VectorStore.new(@db_path)

    @llm_router = RepligenNLU::LLMRouter.new

    @agent = RepligenNLU::ConversationalAgent.new(@vector_store, @llm_router)

    true

  rescue => e

    puts "[WARNING] NLU initialization failed: #{e.message}"

    puts "[INFO] Falling back to basic mode"

    false

  end

  def setup_welcome
    model_count = get_model_count

    @indexed_count = get_indexed_count

    @welcome_message = <<~WELCOME
      ╔═══════════════════════════════════════════════════════════════╗
      ║           REPLIGEN v2.0 - AI Generation Studio               ║

      ║         Natural Language Understanding Enabled 🤖            ║

      ╚═══════════════════════════════════════════════════════════════╝

      📊 Database: #{format_number(model_count)} Replicate models
      🔍 Vector Search: #{format_number(@indexed_count)} models indexed

      🤖 NLU Status: #{@nlu_enabled ? '✓ Active' : '✗ Disabled'}

      💡 LLM Support: #{@llm_router.instance_variable_get(:@available_providers).map(&:to_s).join(', ')}

    WELCOME
  end

  def run
    puts @welcome_message

    # First-time setup prompts
    if @indexed_count < 100

      puts "⚠️  Vector index empty or small"

      print "Build vector index now? This enables semantic search (Y/n): "

      response = gets&.chomp&.downcase

      if response.empty? || response.start_with?("y")

        @vector_store.index_all_models

        @indexed_count = get_indexed_count

      end

    end

    show_quick_start
    interactive_loop

  end

  def show_quick_start
    puts "\n" + "─" * 65

    puts "QUICK START - Try natural language commands:"

    puts "─" * 65

    puts "  'generate a sunset over mountains'"

    puts "  'search for video animation models'"

    puts "  'build a cinematic chain for portrait photography'"

    puts "  'explain flux model'"

    puts "  'optimize: create product video with music'"

    puts "  'compare imagen3 vs flux'"

    puts ""

    puts "Advanced:"

    puts "  /index              - Rebuild vector search index"

    puts "  /scrape [pages]     - Scrape new models from Replicate"

    puts "  /stats              - Show database statistics"

    puts "  /providers          - List available LLM providers"

    puts "  /help               - Show all commands"

    puts "─" * 65

    puts ""

  end

  def interactive_loop
    loop do

      print "repligen> "

      input = gets&.chomp&.strip

      break if input.nil? || input.empty? || %w[quit exit q bye].include?(input.downcase)

      handle_input(input)
      puts ""

    rescue Interrupt

      puts "\nBye! 👋"

      break

    rescue => e

      puts "❌ Error: #{e.message}"

      puts e.backtrace.first(3).join("\n") if ENV["DEBUG"]

    end

    cleanup
  end

  def handle_input(input)
    # System commands

    return handle_system_command(input) if input.start_with?("/")

    # NLU processing
    if @nlu_enabled

      result = @agent.process(input)

      handle_nlu_result(result, input)

    else

      handle_basic_mode(input)

    end

  end

  def handle_system_command(input)
    parts = input[1..-1].split

    command = parts.shift

    case command
    when "index"

      @vector_store.index_all_models

      @indexed_count = get_indexed_count

      puts "✓ Vector index rebuilt: #{@indexed_count} models"

    when "scrape"
      pages = (parts.first || 50).to_i

      puts "🔍 Scraping #{pages} pages from replicate.com/explore..."

      system("ruby33 scrape_replicate_explore.rb")

      puts "✓ Scraping complete. Run /index to update vector search."

    when "stats"
      show_stats

    when "providers"
      show_providers

    when "help"
      show_help

    when "export"
      export_models(parts.first || "models_export.json")

    when "config"
      show_config

    else
      puts "Unknown command: /#{command}"

      puts "Try /help for available commands"

    end

  end

  def handle_nlu_result(result, original_input)
    case result[:intent]

    when :search

      display_search_results(result)

    when :generate
      execute_generation(result, original_input)

    when :chain
      execute_chain(result, original_input)

    when :explain
      display_explanation(result)

    when :compare
      display_comparison(result)

    when :optimize
      display_optimization(result)

    else
      puts result[:message] || "Unknown intent"

      puts result[:suggestion] if result[:suggestion]

    end

  end

  def display_search_results(result)
    puts "\n🔍 Search Results:"

    puts "═" * 65

    if result[:results].empty?
      puts "No models found"

    else

      result[:results].first(10).each_with_index do |model, i|

        similarity = (model["similarity"] * 100).round(1)

        puts "\n#{i + 1}. #{model['id']} (#{similarity}% match)"

        puts "   Type: #{model['type'] || 'unknown'}"

        puts "   Cost: $#{model['cost'] || 0.05}"

        puts "   #{model['description']&.slice(0, 80)}" if model['description']

      end

    end

  end

  def execute_generation(result, prompt)
    recommendation = result[:recommendation]

    if recommendation
      puts "\n🤖 AI Recommendation:"

      puts "═" * 65

      puts "Approach: #{recommendation['approach']}"

      puts "Models: #{recommendation['models']&.map { |m| m['id'] }&.join(' → ')}"

      puts "Cost: $#{recommendation['estimated_cost']}"

      puts "\n#{recommendation['explanation']}"

      puts "═" * 65

      print "\nExecute this recommendation? (Y/n): "
      response = gets&.chomp&.downcase

      if response.empty? || response.start_with?("y")

        puts "\n▶️  Executing via repligen.rb..."

        execute_repligen_command("generate", prompt)

      end

    else

      puts "\n▶️  Generating: #{prompt}"

      execute_repligen_command("generate", prompt)

    end

  end

  def execute_chain(result, prompt)
    recommendation = result[:recommendation]

    if recommendation
      puts "\n🎬 Chain Recommendation:"

      puts "═" * 65

      puts "Style: #{result[:style]}"

      if recommendation['steps']
        puts "\nPipeline:"

        recommendation['steps'].each_with_index do |step, i|

          puts "  #{i + 1}. #{step['model']} - #{step['purpose']}"

        end

        puts "\nTotal Cost: $#{recommendation['total_cost']}"

        puts "\n#{recommendation['explanation']}"

      end

      puts "═" * 65
      print "\nExecute this chain? (Y/n): "
      response = gets&.chomp&.downcase

      if response.empty? || response.start_with?("y")

        execute_repligen_command("chain", "#{result[:style]} #{prompt}")

      end

    else

      execute_repligen_command("chain", "#{result[:style]} #{prompt}")

    end

  end

  def display_explanation(result)
    if result[:model]

      m = result[:model]

      puts "\n📖 Model Information:"

      puts "═" * 65

      puts "ID: #{m['id']}"

      puts "Type: #{m['type'] || 'unknown'}"

      puts "Cost: $#{m['cost'] || 0.05} per run"

      puts "URL: #{m['url']}" if m['url']

      puts "\nDescription:"

      puts m['description'] || 'No description available'

    else

      puts "\n#{result[:message]}"

    end

  end

  def display_comparison(result)
    puts "\n⚖️  Model Comparison:"

    puts "═" * 65

    puts "Comparing: #{result[:models]&.join(' vs ')}"

    puts "\nFetching detailed comparison from vector database..."

    result[:models]&.each do |model_id|
      model = @vector_store.instance_variable_get(:@db).execute(

        "SELECT * FROM models WHERE id = ?",

        [model_id]

      ).first

      if model
        puts "\n• #{model['id']}"

        puts "  Type: #{model['type']}"

        puts "  Cost: $#{model['cost']}"

        puts "  #{model['description']&.slice(0, 100)}"

      end

    end

  end

  def display_optimization(result)
    rec = result[:recommendation]

    puts "\n💡 Optimization Recommendation:"
    puts "═" * 65

    if rec
      puts "Approach: #{rec['approach']}"

      puts "Models: #{rec['models']&.join(' → ')}"

      puts "Cost: $#{rec['cost']}"

      puts "\n#{rec['reasoning']}"

    else

      puts "Could not generate optimization - try rephrasing"

    end

  end

  def execute_repligen_command(cmd, args)
    # Execute original repligen.rb commands

    system("ruby33 repligen.rb #{cmd} #{args}")

  end

  def handle_basic_mode(input)
    # Fallback for when NLU is disabled

    puts "⚠️  NLU disabled - using basic mode"

    if input.match?(/\b(search|find)\b/i)
      query = input.gsub(/\b(search|find)\b/i, '').strip

      basic_search(query)

    else

      puts "Executing: generate #{input}"

      execute_repligen_command("generate", input)

    end

  end

  def basic_search(query)
    db = SQLite3::Database.new(@db_path)

    db.results_as_hash = true

    results = db.execute(
      "SELECT * FROM models WHERE id LIKE ? OR description LIKE ? LIMIT 10",

      ["%#{query}%", "%#{query}%"]

    )

    if results.empty?
      puts "No models found for: #{query}"

    else

      puts "\nFound #{results.size} models:"

      results.each do |m|

        puts "  • #{m['id']} (#{m['type']}) - $#{m['cost']}"

      end

    end

    db.close
  end

  def show_stats
    db = SQLite3::Database.new(@db_path)

    db.results_as_hash = true

    total = db.execute("SELECT COUNT(*) as count FROM models")[0]["count"]
    by_type = db.execute(

      "SELECT type, COUNT(*) as count FROM models WHERE type IS NOT NULL GROUP BY type ORDER BY count DESC LIMIT 10"

    )

    indexed = db.execute("SELECT COUNT(*) as count FROM model_embeddings")[0]["count"]

    puts "\n📊 Database Statistics:"
    puts "═" * 65

    puts "Total models: #{format_number(total)}"

    puts "Vector indexed: #{format_number(indexed)}"

    puts "\nTop Categories:"

    by_type.each do |row|

      puts "  #{row['type'].ljust(20)} #{format_number(row['count']).rjust(8)}"

    end

    db.close
  end

  def show_providers
    puts "\n🔌 LLM Providers:"

    puts "═" * 65

    RepligenNLU::LLMRouter::PROVIDERS.each do |name, config|
      status = ENV[config[:env_key]] ? "✓ Active" : "✗ Not configured"

      puts "#{name.to_s.ljust(10)} #{config[:model].ljust(30)} #{status}"

    end

    puts "\nTo enable:"
    puts "  Claude: export ANTHROPIC_API_KEY=your_key"

    puts "  Grok:   export XAI_API_KEY=your_key"

    puts "  GPT:    export OPENAI_API_KEY=your_key"

  end

  def show_config
    puts "\n⚙️  Configuration:"

    puts "═" * 65

    puts "Database: #{@db_path}"

    puts "NLU Enabled: #{@nlu_enabled}"

    puts "Models Count: #{get_model_count}"

    puts "Indexed: #{@indexed_count}"

    puts "\nEnvironment Variables:"

    %w[ANTHROPIC_API_KEY XAI_API_KEY OPENAI_API_KEY REPLICATE_API_TOKEN].each do |var|

      status = ENV[var] ? "✓ Set" : "✗ Not set"

      puts "  #{var.ljust(25)} #{status}"

    end

  end

  def show_help
    puts "\n📚 Repligen v2.0 Help:"

    puts "═" * 65

    puts "\nNatural Language Commands:"

    puts "  generate <description>       - Generate content"

    puts "  search <query>               - Search for models"

    puts "  build/chain <description>    - Create processing chain"

    puts "  explain <model>              - Explain model details"

    puts "  compare <model1> vs <model2> - Compare models"

    puts "  optimize <task>              - Optimize for cost/quality"

    puts "\nSystem Commands:"

    puts "  /index                       - Rebuild vector search"

    puts "  /scrape [pages]              - Scrape Replicate models"

    puts "  /stats                       - Database statistics"

    puts "  /providers                   - List LLM providers"

    puts "  /config                      - Show configuration"

    puts "  /export [file]               - Export models to JSON"

    puts "  /help                        - This help message"

    puts "\nExamples:"

    puts "  'generate cyberpunk cityscape at night'"

    puts "  'search for realistic portrait models'"

    puts "  'build cinematic video with orchestral music'"

    puts "  'optimize: create instagram reel from photos'"

  end

  def export_models(filename)
    db = SQLite3::Database.new(@db_path)

    db.results_as_hash = true

    models = db.execute("SELECT * FROM models")
    File.write(filename, JSON.pretty_generate(models))

    puts "✓ Exported #{models.size} models to #{filename}"
    db.close

  end

  def get_model_count
    db = SQLite3::Database.new(@db_path)

    count = db.execute("SELECT COUNT(*) as count FROM models")[0][0] rescue 0

    db.close

    count

  end

  def get_indexed_count
    db = SQLite3::Database.new(@db_path)

    count = db.execute("SELECT COUNT(*) as count FROM model_embeddings")[0][0] rescue 0

    db.close

    count

  end

  def format_number(num)
    num.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse

  end

  def cleanup
    @vector_store&.close

    puts "\nSession ended. Models ready for generation! 🚀"

  end

end

# Entry point
if __FILE__ == $0

  repligen = RepligenV2.new

  repligen.run

end

