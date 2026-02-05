# frozen_string_literal: true

require 'digest'
require 'json'

module MASTER
  # Semantic caching with embeddings for fast LLM response retrieval
  class SemanticCache
    CACHE_DIR = File.join(Paths.var, 'semantic_cache')
    SIMILARITY_THRESHOLD = 0.85
    MAX_CACHE_SIZE = 1000
    
    def initialize(llm: nil)
      @llm = llm || LLM.new
      @cache = {}
      @embeddings = {}
      FileUtils.mkdir_p(CACHE_DIR)
      load_cache
    end
    
    # Check cache for semantically similar query
    def get(query, model: nil)
      query_embedding = embed(query)
      
      # Find most similar cached query
      best_match = find_best_match(query_embedding)
      
      return nil unless best_match
      return nil if best_match[:similarity] < SIMILARITY_THRESHOLD
      
      # Return cached response if model matches or no model specified
      cached = @cache[best_match[:key]]
      return nil if model && cached[:model] != model
      
      puts "Cache hit (#{(best_match[:similarity] * 100).round}% similarity)" if ENV['DEBUG']
      cached[:response]
    end
    
    # Store query and response with embedding
    def set(query, response, model: nil, metadata: {})
      key = cache_key(query)
      embedding = embed(query)
      
      @cache[key] = {
        query: query,
        response: response,
        model: model,
        embedding: embedding,
        metadata: metadata,
        created_at: Time.now.to_i,
        hits: 0
      }
      
      @embeddings[key] = embedding
      
      # Prune if cache too large
      prune_cache if @cache.size > MAX_CACHE_SIZE
      
      save_cache
      response
    end
    
    # Clear entire cache
    def clear
      @cache.clear
      @embeddings.clear
      FileUtils.rm_rf(Dir[File.join(CACHE_DIR, '*.json')])
    end
    
    # Get cache statistics
    def stats
      {
        size: @cache.size,
        total_hits: @cache.values.sum { |v| v[:hits] },
        avg_similarity: avg_similarity,
        oldest_entry: oldest_entry,
        newest_entry: newest_entry
      }
    end
    
    private
    
    # Generate embedding for text (simplified - use real embedding model in production)
    def embed(text)
      # In production, use: @llm.embed(text) or OpenAI embeddings
      # For now, use simple character frequency as poor man's embedding
      chars = text.downcase.chars
      vec = Array.new(128, 0)
      chars.each { |c| vec[c.ord % 128] += 1 }
      normalize(vec)
    end
    
    # Cosine similarity between two vectors
    def cosine_similarity(a, b)
      dot_product = a.zip(b).map { |x, y| x * y }.sum
      magnitude_a = Math.sqrt(a.map { |x| x * x }.sum)
      magnitude_b = Math.sqrt(b.map { |x| x * x }.sum)
      
      return 0 if magnitude_a == 0 || magnitude_b == 0
      
      dot_product / (magnitude_a * magnitude_b)
    end
    
    # Find best matching cached query
    def find_best_match(query_embedding)
      return nil if @embeddings.empty?
      
      similarities = @embeddings.map do |key, embedding|
        {
          key: key,
          similarity: cosine_similarity(query_embedding, embedding)
        }
      end
      
      best = similarities.max_by { |s| s[:similarity] }
      
      # Increment hit counter
      if best && best[:similarity] >= SIMILARITY_THRESHOLD
        @cache[best[:key]][:hits] += 1
      end
      
      best
    end
    
    # Normalize vector to unit length
    def normalize(vec)
      magnitude = Math.sqrt(vec.map { |x| x * x }.sum)
      return vec if magnitude == 0
      
      vec.map { |x| x / magnitude }
    end
    
    # Generate cache key
    def cache_key(query)
      Digest::SHA256.hexdigest(query)[0..15]
    end
    
    # Prune least recently used entries
    def prune_cache
      # Remove 20% oldest entries with fewest hits
      remove_count = (MAX_CACHE_SIZE * 0.2).to_i
      
      sorted = @cache.sort_by { |_, v| [v[:hits], v[:created_at]] }
      sorted.first(remove_count).each do |key, _|
        @cache.delete(key)
        @embeddings.delete(key)
      end
    end
    
    # Load cache from disk
    def load_cache
      Dir[File.join(CACHE_DIR, '*.json')].each do |file|
        data = JSON.parse(File.read(file), symbolize_names: true)
        @cache[data[:key]] = data
        @embeddings[data[:key]] = data[:embedding]
      end
    rescue => e
      puts "Failed to load cache: #{e.message}" if ENV['DEBUG']
    end
    
    # Save cache to disk
    def save_cache
      @cache.each do |key, data|
        file = File.join(CACHE_DIR, "#{key}.json")
        File.write(file, JSON.pretty_generate(data.merge(key: key)))
      end
    end
    
    def avg_similarity
      return 0 if @embeddings.size < 2
      
      similarities = @embeddings.values.combination(2).map do |a, b|
        cosine_similarity(a, b)
      end
      
      similarities.sum / similarities.size
    end
    
    def oldest_entry
      @cache.values.min_by { |v| v[:created_at] }&.[](:created_at)
    end
    
    def newest_entry
      @cache.values.max_by { |v| v[:created_at] }&.[](:created_at)
    end
  end
end
