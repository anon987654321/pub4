# frozen_string_literal: true

require 'yaml'
require 'json'
require 'fileutils'
require 'digest'
require 'time'
require 'net/http'

module MASTER
  # Weaviate vector database wrapper
  # Weaviate is the backend for memory storage, providing semantic memory,
  # similarity search, and concept storage capabilities
  class Weaviate
    DEFAULT_HOST = ENV.fetch('WEAVIATE_HOST', 'localhost')
    DEFAULT_PORT = ENV.fetch('WEAVIATE_PORT', '8080').to_i
    BATCH_SIZE = 100
    TIMEOUT = 30

    def initialize(host: DEFAULT_HOST, port: DEFAULT_PORT, api_key: nil)
      @host = host
      @port = port
      @api_key = api_key || ENV['WEAVIATE_API_KEY']
      @base_url = "http://#{@host}:#{@port}/v1"
    end

    # Health check
    def healthy?
      get('/meta')
      true
    rescue StandardError
      false
    end

    # Create schema class for storing objects
    def create_class(name, properties: [], vectorizer: 'none')
      payload = {
        class: name,
        vectorizer: vectorizer,
        properties: properties.map do |prop|
          { name: prop[:name], dataType: [prop[:type] || 'text'] }
        end
      }
      post('/schema', payload)
    end

    # Delete schema class
    def delete_class(name)
      delete("/schema/#{name}")
    end

    # List all classes
    def list_classes
      response = get('/schema')
      response['classes']&.map { |c| c['class'] } || []
    end

    # Add object with optional vector
    def add(class_name, properties, vector: nil, id: nil)
      payload = { class: class_name, properties: properties }
      payload[:vector] = vector if vector
      payload[:id] = id if id
      post('/objects', payload)
    end

    # Batch add objects
    def batch_add(class_name, objects)
      objects.each_slice(BATCH_SIZE) do |batch|
        payload = {
          objects: batch.map do |obj|
            { class: class_name, properties: obj[:properties], vector: obj[:vector] }
          end
        }
        post('/batch/objects', payload)
      end
    end

    # Get object by ID
    def get_object(class_name, id)
      get("/objects/#{class_name}/#{id}")
    end

    # Delete object by ID
    def delete_object(class_name, id)
      delete("/objects/#{class_name}/#{id}")
    end

    # Vector similarity search
    def search(class_name, vector:, limit: 10, fields: ['*'])
      query = {
        query: graphql_near_vector(class_name, vector, limit, fields)
      }
      response = post('/graphql', query)
      extract_results(response, class_name)
    end

    # Semantic search with text (requires text2vec module)
    def semantic_search(class_name, text:, limit: 10, fields: ['*'])
      query = {
        query: graphql_near_text(class_name, text, limit, fields)
      }
      response = post('/graphql', query)
      extract_results(response, class_name)
    end

    # Hybrid search (vector + keyword)
    def hybrid_search(class_name, query:, vector: nil, limit: 10, fields: ['*'], alpha: 0.5)
      gql = graphql_hybrid(class_name, query, vector, limit, fields, alpha)
      response = post('/graphql', { query: gql })
      extract_results(response, class_name)
    end

    # Count objects in class
    def count(class_name)
      query = {
        query: "{ Aggregate { #{class_name} { meta { count } } } }"
      }
      response = post('/graphql', query)
      response.dig('data', 'Aggregate', class_name, 0, 'meta', 'count') || 0
    end

    # Store code snippet with embedding
    def store_code(code, metadata = {})
      ensure_code_class
      properties = {
        content: code[0..10_000],
        language: metadata[:language] || 'ruby',
        file: metadata[:file] || 'unknown',
        timestamp: Time.now.iso8601
      }
      add('CodeSnippet', properties, vector: metadata[:vector])
    end

    # Store principle for semantic matching
    def store_principle(name, description, examples = [])
      ensure_principles_class
      properties = {
        name: name,
        description: description,
        examples: examples.join("\n")
      }
      add('Principle', properties)
    end

    # Store memory/context for sessions
    def store_memory(content, session_id:, type: 'context')
      ensure_memory_class
      properties = {
        content: content[0..50_000],
        session_id: session_id,
        type: type,
        timestamp: Time.now.iso8601
      }
      add('Memory', properties)
    end

    # Find similar code
    def find_similar_code(vector, limit: 5)
      search('CodeSnippet', vector: vector, limit: limit, fields: %w[content language file])
    end

    # Find relevant principles
    def find_principles(text, limit: 5)
      semantic_search('Principle', text: text, limit: limit, fields: %w[name description examples])
    end

    # Retrieve session memories
    def recall_memories(session_id, limit: 20)
      query = {
        query: <<~GQL
          {
            Get {
              Memory(
                where: { path: ["session_id"], operator: Equal, valueText: "#{session_id}" }
                limit: #{limit}
              ) { content type timestamp }
            }
          }
        GQL
      }
      response = post('/graphql', query)
      extract_results(response, 'Memory')
    end

    private

    def ensure_code_class
      return if list_classes.include?('CodeSnippet')
      create_class('CodeSnippet', properties: [
        { name: 'content', type: 'text' },
        { name: 'language', type: 'text' },
        { name: 'file', type: 'text' },
        { name: 'timestamp', type: 'text' }
      ])
    end

    def ensure_principles_class
      return if list_classes.include?('Principle')
      create_class('Principle', properties: [
        { name: 'name', type: 'text' },
        { name: 'description', type: 'text' },
        { name: 'examples', type: 'text' }
      ])
    end

    def ensure_memory_class
      return if list_classes.include?('Memory')
      create_class('Memory', properties: [
        { name: 'content', type: 'text' },
        { name: 'session_id', type: 'text' },
        { name: 'type', type: 'text' },
        { name: 'timestamp', type: 'text' }
      ])
    end

    def graphql_near_vector(class_name, vector, limit, fields)
      <<~GQL
        {
          Get {
            #{class_name}(
              nearVector: { vector: #{vector.to_json} }
              limit: #{limit}
            ) { #{fields.join(' ')} _additional { distance } }
          }
        }
      GQL
    end

    def graphql_near_text(class_name, text, limit, fields)
      <<~GQL
        {
          Get {
            #{class_name}(
              nearText: { concepts: #{[text].to_json} }
              limit: #{limit}
            ) { #{fields.join(' ')} _additional { distance } }
          }
        }
      GQL
    end

    def graphql_hybrid(class_name, query, vector, limit, fields, alpha)
      vector_part = vector ? ", vector: #{vector.to_json}" : ''
      <<~GQL
        {
          Get {
            #{class_name}(
              hybrid: { query: #{query.to_json}, alpha: #{alpha}#{vector_part} }
              limit: #{limit}
            ) { #{fields.join(' ')} _additional { score } }
          }
        }
      GQL
    end

    def extract_results(response, class_name)
      response.dig('data', 'Get', class_name) || []
    end

    def get(path)
      request(Net::HTTP::Get, path)
    end

    def post(path, body)
      request(Net::HTTP::Post, path, body)
    end

    def delete(path)
      request(Net::HTTP::Delete, path)
    end

    def request(method_class, path, body = nil)
      uri = URI("#{@base_url}#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.read_timeout = TIMEOUT

      req = method_class.new(uri)
      req['Content-Type'] = 'application/json'
      req['Authorization'] = "Bearer #{@api_key}" if @api_key
      req.body = body.to_json if body

      response = http.request(req)
      JSON.parse(response.body)
    rescue JSON::ParserError
      {}
    end
  end

  # Vector-based memory with embedding and retrieval
  # Implements chunking, storage, and similarity search with recency reranking
  class Memory
    CHUNK_SIZE = 750        # tokens per chunk
    CHUNK_OVERLAP = 85      # token overlap
    DEFAULT_TOP_K = 5       # default retrieval count
    CHARS_PER_TOKEN = 4     # simple token estimation
    
    attr_reader :chunks, :metadata_store
    
    def initialize
      @chunks = []
      @metadata_store = {}
      @embeddings = {}
    end
    
    # Store content with metadata
    # @param content [String] Content to store
    # @param tags [Array<String>] Tags for categorization
    # @param source [String] Source identifier
    # @return [Array<String>] Chunk IDs
    def store(content, tags: [], source: nil)
      chunk_ids = []
      chunks = chunk_text(content)
      
      chunks.each_with_index do |chunk, idx|
        chunk_id = generate_id(chunk, idx)
        
        @chunks << {
          id: chunk_id,
          content: chunk,
          embedding: compute_embedding(chunk)
        }
        
        @metadata_store[chunk_id] = {
          timestamp: Time.now,
          tags: tags,
          source: source,
          index: idx,
          total_chunks: chunks.size
        }
        
        chunk_ids << chunk_id
      end
      
      chunk_ids
    end
    
    # Recall relevant content by query
    # @param query [String] Search query
    # @param k [Integer] Number of results to return
    # @return [Array<Hash>] Results with content and metadata
    def recall(query, k: DEFAULT_TOP_K)
      return [] if @chunks.empty?
      
      query_embedding = compute_embedding(query)
      
      # Calculate similarity scores
      scored_chunks = @chunks.map do |chunk|
        similarity = cosine_similarity(query_embedding, chunk[:embedding])
        {
          id: chunk[:id],
          content: chunk[:content],
          similarity: similarity,
          metadata: @metadata_store[chunk[:id]]
        }
      end
      
      # Sort by similarity, then rerank by recency
      top_results = scored_chunks.sort_by { |c| -c[:similarity] }.first(k * 2)
      
      # Rerank: boost recent results
      reranked = rerank_by_recency(top_results)
      
      reranked.first(k)
    end
    
    # Save memory to file
    # @param filepath [String] Path to save file
    def save(filepath)
      FileUtils.mkdir_p(File.dirname(filepath))
      
      data = {
        chunks: @chunks,
        metadata: @metadata_store,
        saved_at: Time.now.iso8601
      }
      
      case File.extname(filepath)
      when '.json'
        File.write(filepath, JSON.pretty_generate(data))
      when '.yml', '.yaml'
        File.write(filepath, YAML.dump(data))
      else
        raise "Unsupported format: #{filepath}"
      end
    end
    
    # Load memory from file
    # @param filepath [String] Path to load file
    def load(filepath)
      return unless File.exist?(filepath)
      
      data = case File.extname(filepath)
             when '.json'
               JSON.parse(File.read(filepath), symbolize_names: true)
             when '.yml', '.yaml'
               YAML.safe_load(File.read(filepath), permitted_classes: [Time, Symbol], symbolize_names: true)
             else
               raise "Unsupported format: #{filepath}"
             end
      
      @chunks = data[:chunks] || data['chunks'] || []
      @metadata_store = data[:metadata] || data['metadata'] || {}
      
      # Convert string keys to symbols if needed
      @metadata_store = @metadata_store.transform_keys(&:to_sym) if @metadata_store.keys.first.is_a?(String)
    end
    
    # Clear all stored memory
    def clear
      @chunks.clear
      @metadata_store.clear
      @embeddings.clear
    end
    
    # Get memory statistics
    def stats
      {
        total_chunks: @chunks.size,
        total_sources: @metadata_store.values.map { |m| m[:source] }.uniq.size,
        total_tags: @metadata_store.values.flat_map { |m| m[:tags] || [] }.uniq.size,
        oldest_entry: @metadata_store.values.map { |m| m[:timestamp] }.min,
        newest_entry: @metadata_store.values.map { |m| m[:timestamp] }.max
      }
    end
    
    private
    
    # Chunk text into overlapping segments
    def chunk_text(text)
      estimated_tokens = text.length / CHARS_PER_TOKEN
      return [text] if estimated_tokens <= CHUNK_SIZE
      
      words = text.split(/\s+/)
      chunks = []
      current_chunk = []
      current_size = 0
      
      words.each do |word|
        word_tokens = word.length / CHARS_PER_TOKEN
        
        if current_size + word_tokens > CHUNK_SIZE && !current_chunk.empty?
          chunks << current_chunk.join(' ')
          
          # Keep overlap
          overlap_words = (CHUNK_OVERLAP * CHARS_PER_TOKEN / 
                           (current_chunk.join(' ').length / current_chunk.size)).to_i
          current_chunk = current_chunk.last([overlap_words, current_chunk.size].min)
          current_size = current_chunk.join(' ').length / CHARS_PER_TOKEN
        end
        
        current_chunk << word
        current_size += word_tokens
      end
      
      chunks << current_chunk.join(' ') unless current_chunk.empty?
      chunks
    end
    
    # Generate unique ID for chunk
    def generate_id(content, index)
      Digest::SHA256.hexdigest("#{content}#{index}#{Time.now.to_f}")[0..15]
    end
    
    # Compute simple embedding (TF-IDF-like)
    def compute_embedding(text)
      # Normalize and tokenize
      words = text.downcase.gsub(/[^\w\s]/, '').split(/\s+/)
      
      # Simple term frequency
      freq = Hash.new(0)
      words.each { |word| freq[word] += 1 }
      
      # Create vector from top terms
      top_terms = freq.sort_by { |_, count| -count }.first(100).to_h
      
      # Normalize to unit vector
      magnitude = Math.sqrt(top_terms.values.sum { |v| v * v })
      return top_terms if magnitude.zero?
      
      top_terms.transform_values { |v| v.to_f / magnitude }
    end
    
    # Cosine similarity between embeddings
    def cosine_similarity(embedding1, embedding2)
      all_keys = (embedding1.keys + embedding2.keys).uniq
      
      dot_product = all_keys.sum do |key|
        (embedding1[key] || 0) * (embedding2[key] || 0)
      end
      
      # Already normalized, so just return dot product
      dot_product
    end
    
    # Rerank results by recency
    def rerank_by_recency(results)
      return results if results.empty?
      
      # Calculate recency score (hours ago)
      now = Time.now
      results.each do |result|
        age_hours = (now - result[:metadata][:timestamp]) / 3600.0
        # Exponential decay: 0.99^hours
        recency_boost = 0.99 ** age_hours
        # Combined score: 70% similarity, 30% recency
        result[:combined_score] = (0.7 * result[:similarity]) + (0.3 * recency_boost)
      end
      
      results.sort_by { |r| -r[:combined_score] }
    end
  end

  # Enhanced vector-based long-term memory using Weaviate
  class VectorMemory
    CHUNK_SIZE = 750
    CHUNK_OVERLAP = 75
    RECENCY_DECAY_HOURS = 168.0  # 1 week decay period

    def initialize
      @weaviate = Weaviate.new
      @last_recall = nil
      ensure_schema_exists
    end

    # Store content with metadata
    def store(content, metadata = {})
      chunks = chunk_text(content)

      chunks.each_with_index do |chunk, i|
        @weaviate.add(
          "MasterMemory",
          {
            content: chunk,
            chunk_index: i,
            timestamp: Time.now.to_i,
            source: metadata[:source] || "unknown",
            tags: (metadata[:tags] || []).join(","),
            context: metadata[:context] || ""
          }
        )
      end

      chunks.size
    end

    # Semantic search with recency ranking
    def recall(query, k: 5, min_relevance: 0.7)
      @last_recall = Time.now

      results = @weaviate.semantic_search(
        "MasterMemory",
        text: query,
        limit: k * 2,  # Get more, then rerank
        fields: %w[content timestamp source tags]
      )

      # Rerank by recency
      ranked = results
        .select { |r| r.dig("_additional", "distance") && (1 - r["_additional"]["distance"]) >= min_relevance }
        .sort_by { |r| -(1 - r["_additional"]["distance"]) * recency_weight(r["timestamp"]) }
        .first(k)

      ranked.map do |r|
        {
          content: r["content"],
          relevance: 1 - r["_additional"]["distance"],
          timestamp: Time.at(r["timestamp"]),
          source: r["source"],
          tags: r["tags"].to_s.split(",")
        }
      end
    end

    # Search by tags
    def find_by_tag(tag, limit: 10)
      results = @weaviate.semantic_search(
        "MasterMemory",
        text: tag,
        limit: limit,
        fields: %w[content timestamp source tags]
      )

      results.select { |r| r["tags"].to_s.include?(tag) }
    end

    # Get recent memories
    def recent(limit: 10)
      @weaviate.semantic_search(
        "MasterMemory",
        text: "recent",
        limit: limit,
        fields: %w[content timestamp source tags]
      ).sort_by { |r| -r["timestamp"] }
    rescue StandardError
      []
    end

    # Stats for dashboard
    def count_chunks
      @weaviate.count("MasterMemory")
    rescue StandardError
      0
    end

    def count_vectors
      count_chunks  # Same as chunks in our case
    end

    def time_since_last_recall
      return "never" unless @last_recall

      seconds = Time.now - @last_recall

      return "just now" if seconds < 60
      return "#{(seconds / 60).to_i}m ago" if seconds < 3600

      "#{(seconds / 3600).to_i}h ago"
    end

    def healthy?
      @weaviate.healthy?
    rescue StandardError
      false
    end

    # Clear all memory (use with caution!)
    def clear!
      @weaviate.delete_class("MasterMemory")
      ensure_schema_exists
    end

    private

    def ensure_schema_exists
      return if @weaviate.list_classes.include?("MasterMemory")

      @weaviate.create_class(
        "MasterMemory",
        properties: [
          { name: "content", type: "text" },
          { name: "chunk_index", type: "int" },
          { name: "timestamp", type: "int" },
          { name: "source", type: "string" },
          { name: "tags", type: "string" },
          { name: "context", type: "text" }
        ],
        vectorizer: "text2vec-openai"
      )
    rescue StandardError => e
      # Silently fail if Weaviate not available
      nil
    end

    def chunk_text(text)
      words = text.split(/\s+/)
      chunks = []

      i = 0
      while i < words.length
        chunk_words = words[i, CHUNK_SIZE]
        chunks << chunk_words.join(" ")

        # Overlap for context
        i += CHUNK_SIZE - CHUNK_OVERLAP
      end

      chunks
    end

    def recency_weight(timestamp)
      age_hours = (Time.now.to_i - timestamp) / 3600.0

      # Decay over time: fresh = 1.0, 24h old = 0.5, 7d old = 0.1
      Math.exp(-age_hours / RECENCY_DECAY_HOURS)
    end
  end
end
