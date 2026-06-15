#!/usr/bin/env ruby33
# frozen_string_literal: true

# Repligen NLU Layer - Natural Language Understanding with LangChainRB
# Supports: Claude, Grok (xAI), GPT, with vector search via sqlite-vec

require "net/http"
require "json"

require "sqlite3"

module RepligenNLU
  VERSION = "1.0.0"

  class VectorStore
    def initialize(db_path = "repligen_models.db")

      @db = SQLite3::Database.new(db_path)

      @db.results_as_hash = true

      setup_vector_tables

      @embedding_cache = {}

    end

    def setup_vector_tables
      # Create vector extension table for embeddings

      @db.execute <<-SQL

        CREATE TABLE IF NOT EXISTS model_embeddings (

          model_id TEXT PRIMARY KEY,

          embedding BLOB,

          created_at INTEGER,

          FOREIGN KEY(model_id) REFERENCES models(id)

        )

      SQL

      # Index for fast lookups
      @db.execute "CREATE INDEX IF NOT EXISTS idx_model_id ON model_embeddings(model_id)"

    rescue SQLite3::Exception => e

      puts "[NLU] Vector table setup: #{e.message}"

    end

    def embed_text(text, provider = :claude)
      # Generate embedding using selected LLM provider

      case provider

      when :claude

        embed_with_claude(text)

      when :openai

        embed_with_openai(text)

      else

        simple_hash_embedding(text)

      end

    end

    def embed_with_claude(text)
      # Claude doesn't have embeddings API, use hash-based for now

      simple_hash_embedding(text)

    end

    def embed_with_openai(text)
      return simple_hash_embedding(text) unless ENV["OPENAI_API_KEY"]

      uri = URI("https://api.openai.com/v1/embeddings")
      req = Net::HTTP::Post.new(uri)

      req["Authorization"] = "Bearer #{ENV['OPENAI_API_KEY']}"

      req["Content-Type"] = "application/json"

      req.body = JSON.generate({

        model: "text-embedding-3-small",

        input: text

      })

      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 30) { |http| http.request(req) }
      return simple_hash_embedding(text) unless res.code == "200"

      data = JSON.parse(res.body)
      data.dig("data", 0, "embedding")

    rescue => e

      puts "[NLU] OpenAI embedding failed: #{e.message}"

      simple_hash_embedding(text)

    end

    def simple_hash_embedding(text)
      # Simple word-based embedding for fallback

      words = text.downcase.scan(/\w+/)

      vector = Array.new(384, 0.0)

      words.each_with_index do |word, i|
        hash = word.bytes.sum % 384

        vector[hash] += 1.0 / (i + 1)

      end

      # Normalize
      magnitude = Math.sqrt(vector.sum { |v| v * v })

      vector.map! { |v| v / (magnitude + 1e-10) }

      vector

    end

    def index_model(model_id, description)
      embedding = embed_text("#{model_id} #{description}")

      blob = embedding.pack("f*")

      @db.execute(
        "INSERT OR REPLACE INTO model_embeddings (model_id, embedding, created_at) VALUES (?, ?, ?)",

        [model_id, blob, Time.now.to_i]

      )

    end

    def semantic_search(query, limit: 10)
      query_embedding = embed_text(query)

      # Get all models with embeddings
      rows = @db.execute("SELECT model_id, embedding FROM model_embeddings")

      similarities = rows.map do |row|
        model_id = row["model_id"]

        stored_embedding = row["embedding"].unpack("f*")

        similarity = cosine_similarity(query_embedding, stored_embedding)

        { model_id: model_id, similarity: similarity }

      end

      # Sort by similarity and get top results
      top_results = similarities.sort_by { |r| -r[:similarity] }.first(limit)

      # Fetch full model data
      top_results.map do |result|

        model_data = @db.execute(

          "SELECT * FROM models WHERE id = ?",

          [result[:model_id]]

        ).first

        model_data.merge("similarity" => result[:similarity]) if model_data
      end.compact

    end

    def cosine_similarity(vec1, vec2)
      return 0.0 if vec1.nil? || vec2.nil? || vec1.size != vec2.size

      dot_product = vec1.zip(vec2).sum { |a, b| a * b }
      magnitude1 = Math.sqrt(vec1.sum { |v| v * v })

      magnitude2 = Math.sqrt(vec2.sum { |v| v * v })

      dot_product / (magnitude1 * magnitude2 + 1e-10)
    end

    def index_all_models
      models = @db.execute("SELECT id, description FROM models WHERE description IS NOT NULL")

      puts "[NLU] Indexing #{models.size} models for vector search..."
      models.each_with_index do |model, i|
        index_model(model["id"], model["description"] || "")

        print "\r[NLU] Indexed: #{i + 1}/#{models.size}" if i % 100 == 0

      end

      puts "\n[NLU] ✓ Vector indexing complete"
    end

    def close
      @db.close

    end

  end

  class LLMRouter
    PROVIDERS = {

      claude: {

        api_url: "https://api.anthropic.com/v1/messages",

        model: "claude-sonnet-4-20250514",

        env_key: "ANTHROPIC_API_KEY",

        header_key: "x-api-key",

        version_header: { "anthropic-version" => "2023-06-01" }

      },

      grok: {

        api_url: "https://api.x.ai/v1/chat/completions",

        model: "grok-beta",

        env_key: "XAI_API_KEY",

        header_key: "Authorization",

        bearer: true

      },

      gpt: {

        api_url: "https://api.openai.com/v1/chat/completions",

        model: "gpt-4-turbo-preview",

        env_key: "OPENAI_API_KEY",

        header_key: "Authorization",

        bearer: true

      }

    }

    def initialize
      @available_providers = detect_available_providers

      puts "[NLU] Available LLMs: #{@available_providers.join(', ')}"

    end

    def detect_available_providers
      PROVIDERS.keys.select { |p| ENV[PROVIDERS[p][:env_key]] }

    end

    def query(prompt, provider: nil, max_tokens: 2000)
      provider ||= @available_providers.first

      unless provider && @available_providers.include?(provider)
        return fallback_response(prompt)

      end

      case provider
      when :claude

        query_claude(prompt, max_tokens)

      when :grok

        query_grok(prompt, max_tokens)

      when :gpt

        query_gpt(prompt, max_tokens)

      else

        fallback_response(prompt)

      end

    end

    def query_claude(prompt, max_tokens)
      config = PROVIDERS[:claude]

      uri = URI(config[:api_url])

      req = Net::HTTP::Post.new(uri)

      req[config[:header_key]] = ENV[config[:env_key]]

      req["Content-Type"] = "application/json"

      config[:version_header].each { |k, v| req[k] = v }

      req.body = JSON.generate({
        model: config[:model],

        max_tokens: max_tokens,

        messages: [{ role: "user", content: prompt }]

      })

      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 60) { |http| http.request(req) }
      return nil unless res.code == "200"

      JSON.parse(res.body).dig("content", 0, "text")
    rescue => e

      puts "[NLU] Claude query failed: #{e.message}"

      nil

    end

    def query_grok(prompt, max_tokens)
      config = PROVIDERS[:grok]

      uri = URI(config[:api_url])

      req = Net::HTTP::Post.new(uri)

      req[config[:header_key]] = "Bearer #{ENV[config[:env_key]]}"

      req["Content-Type"] = "application/json"

      req.body = JSON.generate({
        model: config[:model],

        max_tokens: max_tokens,

        messages: [{ role: "user", content: prompt }]

      })

      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 60) { |http| http.request(req) }
      return nil unless res.code == "200"

      JSON.parse(res.body).dig("choices", 0, "message", "content")
    rescue => e

      puts "[NLU] Grok query failed: #{e.message}"

      nil

    end

    def query_gpt(prompt, max_tokens)
      config = PROVIDERS[:gpt]

      uri = URI(config[:api_url])

      req = Net::HTTP::Post.new(uri)

      req[config[:header_key]] = "Bearer #{ENV[config[:env_key]]}"

      req["Content-Type"] = "application/json"

      req.body = JSON.generate({
        model: config[:model],

        max_tokens: max_tokens,

        messages: [{ role: "user", content: prompt }]

      })

      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 60) { |http| http.request(req) }
      return nil unless res.code == "200"

      JSON.parse(res.body).dig("choices", 0, "message", "content")
    rescue => e

      puts "[NLU] GPT query failed: #{e.message}"

      nil

    end

    def fallback_response(prompt)
      # Rule-based fallback when no LLM available

      if prompt.match?(/video/i)

        { suggestion: "wan480 or sdv for video generation" }

      elsif prompt.match?(/image|photo/i)

        { suggestion: "imagen3 or flux for image generation" }

      elsif prompt.match?(/music|audio/i)

        { suggestion: "music model for audio" }

      else

        { suggestion: "quick chain for general generation" }

      end.to_json

    end

  end

  class IntentClassifier
    INTENTS = {

      generate: /\b(generate|create|make|build|produce|draw|paint|render)\b/i,

      search: /\b(search|find|look for|show me|list|browse)\b/i,

      chain: /\b(chain|pipeline|workflow|multi-step|sequence)\b/i,

      explain: /\b(explain|what is|how does|tell me about|describe)\b/i,

      compare: /\b(compare|versus|vs|difference|better)\b/i,

      optimize: /\b(optimize|improve|enhance|best|fastest|cheapest)\b/i

    }

    def self.classify(input)
      INTENTS.each do |intent, pattern|

        return intent if input.match?(pattern)

      end

      :generate # Default intent

    end

    def self.extract_params(input, intent)
      params = {}

      case intent
      when :generate

        params[:prompt] = input.gsub(INTENTS[:generate], '').strip

        params[:chain_type] = detect_chain_type(input)

      when :search

        params[:query] = input.gsub(INTENTS[:search], '').strip

      when :chain

        params[:style] = extract_style(input)

        params[:prompt] = input.gsub(INTENTS[:chain], '').strip

      when :compare

        params[:models] = extract_model_names(input)

      end

      params
    end

    def self.detect_chain_type(input)
      return :video if input.match?(/\b(video|motion|animate|movie)\b/i)

      return :full if input.match?(/\b(full|complete|with music|with sound)\b/i)

      return :creative if input.match?(/\b(creative|artistic|experimental)\b/i)

      :quick

    end

    def self.extract_style(input)
      return "cinematic" if input.match?(/\b(cinematic|film|movie)\b/i)

      return "dramatic" if input.match?(/\b(dramatic|intense)\b/i)

      return "experimental" if input.match?(/\b(experimental|chaos|random)\b/i)

      "cinematic"

    end

    def self.extract_model_names(input)
      # Extract model IDs from input

      input.scan(/[\w-]+\/[\w-]+/).uniq

    end

  end

  class ConversationalAgent
    def initialize(vector_store, llm_router)

      @vector_store = vector_store

      @llm_router = llm_router

      @context = []

    end

    def process(user_input)
      # Classify intent

      intent = IntentClassifier.classify(user_input)

      params = IntentClassifier.extract_params(user_input, intent)

      # Add to conversation context
      @context << { role: "user", content: user_input }

      case intent
      when :search

        handle_search(params[:query])

      when :generate

        handle_generate(params)

      when :chain

        handle_chain(params)

      when :explain

        handle_explain(user_input)

      when :compare

        handle_compare(params[:models])

      when :optimize

        handle_optimize(user_input)

      else

        handle_fallback(user_input)

      end

    end

    def handle_search(query)
      results = @vector_store.semantic_search(query, limit: 10)

      {
        intent: :search,

        results: results,

        summary: format_search_results(results)

      }

    end

    def handle_generate(params)
      # Use LLM to suggest best generation approach

      prompt = build_generation_prompt(params[:prompt], params[:chain_type])

      response = @llm_router.query(prompt, max_tokens: 1000)

      parse_llm_recommendation(response) || {
        intent: :generate,

        chain_type: params[:chain_type],

        prompt: params[:prompt]

      }

    end

    def handle_chain(params)
      # Build optimal chain based on style and prompt

      relevant_models = @vector_store.semantic_search(params[:prompt], limit: 20)

      prompt = build_chain_prompt(params[:prompt], params[:style], relevant_models)
      response = @llm_router.query(prompt, max_tokens: 1500)

      {
        intent: :chain,

        style: params[:style],

        recommendation: parse_chain_response(response),

        models: relevant_models.first(5)

      }

    end

    def handle_explain(query)
      models = @vector_store.semantic_search(query, limit: 3)

      if models.any?
        model = models.first

        {

          intent: :explain,

          model: model,

          explanation: "#{model['id']}: #{model['description']}"

        }

      else

        {

          intent: :explain,

          message: "No models found for: #{query}"

        }

      end

    end

    def handle_compare(model_ids)
      {

        intent: :compare,

        models: model_ids,

        message: "Comparing: #{model_ids.join(' vs ')}"

      }

    end

    def handle_optimize(query)
      prompt = <<~PROMPT

        Optimize this AI generation request for cost and quality: "#{query}"

        Suggest:
        1. Most cost-effective model chain

        2. Quality vs speed tradeoffs

        3. Estimated costs

        Respond as JSON with: {approach, models, cost, reasoning}
      PROMPT

      response = @llm_router.query(prompt)
      {
        intent: :optimize,

        recommendation: parse_optimization(response)

      }

    end

    def handle_fallback(input)
      {

        intent: :unknown,

        message: "I can help with: generate, search, chain, explain, compare, optimize",

        suggestion: "Try: 'generate a sunset photo' or 'search for video models'"

      }

    end

    private
    def build_generation_prompt(user_prompt, chain_type)
      <<~PROMPT

        User wants to generate: "#{user_prompt}"

        Preferred chain type: #{chain_type}

        From these Replicate models, suggest the best approach:
        - imagen3 ($0.01): Fast image generation

        - flux ($0.03): High-quality photorealistic

        - wan480 ($0.08): Image to video

        - music ($0.02): Audio generation

        - upscale ($0.002): 4x upscaling

        Respond as JSON:
        {

          "approach": "single|chain",

          "models": [{"id": "model-name", "reasoning": "why"}],

          "estimated_cost": 0.05,

          "explanation": "brief summary"

        }

      PROMPT

    end

    def build_chain_prompt(user_prompt, style, models)
      models_summary = models.first(10).map do |m|

        "- #{m['id']} (#{m['type']}, $#{m['cost'] || 0.05})"

      end.join("\n")

      <<~PROMPT
        Build a #{style} generation chain for: "#{user_prompt}"

        Available models:
        #{models_summary}

        Design a 3-8 step pipeline. Respond as JSON:
        {

          "steps": [{"model": "id", "purpose": "what it does"}],

          "total_cost": 0.15,

          "explanation": "why this chain works"

        }

      PROMPT

    end

    def format_search_results(results)
      if results.empty?

        "No models found"

      else

        "Found #{results.size} models:\n" + results.first(5).map do |m|

          "• #{m['id']} (#{m['type']}) - #{m['description']&.slice(0, 60)}"

        end.join("\n")

      end

    end

    def parse_llm_recommendation(response)
      return nil unless response

      json_match = response.match(/\{[\s\S]*\}/)
      return nil unless json_match

      JSON.parse(json_match[0])
    rescue

      nil

    end

    def parse_chain_response(response)
      parse_llm_recommendation(response)

    end

    def parse_optimization(response)
      parse_llm_recommendation(response)

    end

  end

end

# Standalone CLI for testing
if __FILE__ == $0

  puts "Repligen NLU v#{RepligenNLU::VERSION}"

  puts "="*60

  # Initialize components
  vector_store = RepligenNLU::VectorStore.new

  llm_router = RepligenNLU::LLMRouter.new

  agent = RepligenNLU::ConversationalAgent.new(vector_store, llm_router)

  # Index models if needed
  if ARGV.include?("--index")

    vector_store.index_all_models

  end

  # Interactive mode
  puts "\nNLU Agent ready. Try:"

  puts "  'generate a sunset photo'"

  puts "  'search for video models'"

  puts "  'build a cinematic chain for portrait'"

  puts ""

  loop do
    print "> "

    input = gets&.chomp

    break if input.nil? || input.empty? || %w[quit exit q].include?(input.downcase)

    result = agent.process(input)
    puts "\n#{JSON.pretty_generate(result)}\n"

  end

  vector_store.close
end

