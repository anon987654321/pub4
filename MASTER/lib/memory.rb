# frozen_string_literal: true

require 'yaml'
require 'json'
require 'fileutils'
require 'digest'
require 'time'

module MASTER
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
end
