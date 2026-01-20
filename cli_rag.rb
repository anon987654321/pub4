#!/usr/bin/env ruby
# frozen_string_literal: true

# CONVERGENCE CLI - RAG Component
# Production RAG Pipeline with RRF fusion and reranking

module Convergence
  class RAGPipeline
    attr_reader :level, :stats

    LEVELS = %i[full keyword simple].freeze

    def initialize(config = {})
      @level = detect_rag_level
      @chunks = []
      @embeddings = {}
      @metadata = {}
      @config = default_config.merge(config)
      @embedding_provider = detect_embedding_provider
      @stats = { chunks: 0, embeddings: 0, provider: @embedding_provider, level: @level }
    end

    # === INDEXING PIPELINE ===

    def ingest(path, options = {})
      return ingest_directory(path, options) if File.directory?(path)

      text = File.read(path) rescue nil
      return 0 unless text

      chunks = chunk_text(text, source: path)
      indexed_count = 0

      chunks.each do |chunk|
        @chunks << chunk
        @metadata[chunk[:id]] = { source: path, timestamp: Time.now.to_i }
        
        if @level == :full
          embedding = embed(chunk[:text])
          if embedding
            @embeddings[chunk[:id]] = embedding
            indexed_count += 1
          end
        else
          indexed_count += 1
        end
      end

      update_stats
      indexed_count
    end

    def ingest_directory(path, options = {})
      extensions = options[:extensions] || %w[.txt .md .rb .yml .json .html]
      
      files = Dir.glob(File.join(path, "**", "*"))
        .select { |f| File.file?(f) && extensions.include?(File.extname(f).downcase) }
      
      files.sum { |f| ingest(f) }
    end

    # === QUERY PIPELINE ===

    def search(query, k: 5, rerank: true)
      return [] if @chunks.empty?

      case @level
      when :full
        semantic_search(query, k: k, rerank: rerank)
      when :keyword
        keyword_search(query, k: k)
      when :simple
        simple_search(query, k: k)
      end
    end

    def multi_query_search(query, k: 5, rerank: true)
      # Generate multiple query variations for better coverage
      queries = generate_query_variations(query)
      
      # Search with each query
      all_results = queries.flat_map { |q| search(q, k: k * 2, rerank: false) }
      
      # Apply RRF (Reciprocal Rank Fusion)
      fused = reciprocal_rank_fusion(all_results)
      
      # Rerank if requested and available
      final = rerank && @level == :full ? rerank_results(query, fused) : fused
      
      final.first(k)
    end

    def augment(query, k: 3, use_multi_query: false)
      results = use_multi_query ? multi_query_search(query, k: k) : search(query, k: k)
      
      return query if results.empty?

      context = repack_context(results)
      "Context:\n#{context}\n\nQuestion: #{query}"
    end

    # === PRIVATE METHODS ===

    private

    def detect_rag_level
      if has_gem?("neighbor") && has_gem?("baran")
        :full
      elsif has_gem?("baran")
        :keyword
      else
        :simple
      end
    end

    def has_gem?(name)
      begin
        require name
        true
      rescue LoadError
        false
      end
    end

    def detect_embedding_provider
      return :openai if ENV["OPENAI_API_KEY"]
      return :local if system("curl -s http://localhost:11434/api/tags > /dev/null 2>&1")
      :none
    end

    def default_config
      {
        chunk_size: 500,
        chunk_overlap: 50,
        rerank_threshold: 0.5,
        rrf_k: 60  # RRF constant
      }
    end

    def chunk_text(text, source: nil)
      if @level == :full && has_gem?("baran")
        chunk_with_baran(text, source: source)
      else
        simple_chunk(text, source: source)
      end
    end

    def chunk_with_baran(text, source: nil)
      # Use Baran's RecursiveCharacterTextSplitter for smart chunking
      require "baran"
      
      splitter = Baran::RecursiveCharacterTextSplitter.new(
        chunk_size: @config[:chunk_size],
        chunk_overlap: @config[:chunk_overlap],
        separators: ["\n\n", "\n", ". ", " ", ""]
      )
      
      chunks = splitter.split_text(text)
      
      chunks.each_with_index.map do |chunk_text, idx|
        {
          id: "#{idx}_#{Digest::MD5.hexdigest(chunk_text)[0..7]}",
          text: chunk_text.strip,
          source: source,
          idx: idx
        }
      end.compact
    rescue LoadError, NameError
      simple_chunk(text, source: source)
    end

    def simple_chunk(text, source: nil, size: nil)
      size ||= @config[:chunk_size]
      
      # Split on paragraphs first
      paragraphs = text.split(/\n{2,}/)
      
      chunks = []
      current_chunk = ""
      idx = 0
      
      paragraphs.each do |para|
        para = para.strip
        next if para.empty?
        
        if current_chunk.length + para.length > size && !current_chunk.empty?
          chunks << {
            id: "#{idx}_#{Digest::MD5.hexdigest(current_chunk)[0..7]}",
            text: current_chunk,
            source: source,
            idx: idx
          }
          idx += 1
          current_chunk = para
        else
          current_chunk += "\n\n" unless current_chunk.empty?
          current_chunk += para
        end
      end
      
      unless current_chunk.empty?
        chunks << {
          id: "#{idx}_#{Digest::MD5.hexdigest(current_chunk)[0..7]}",
          text: current_chunk,
          source: source,
          idx: idx
        }
      end
      
      chunks
    end

    def embed(text)
      return nil if @embedding_provider == :none

      case @embedding_provider
      when :openai
        embed_openai(text)
      when :local
        embed_ollama(text)
      end
    end

    def embed_openai(text)
      require "net/http"
      require "json"
      
      uri = URI("https://api.openai.com/v1/embeddings")
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{ENV["OPENAI_API_KEY"]}"
      request["Content-Type"] = "application/json"
      request.body = JSON.generate({
        model: "text-embedding-3-small",
        input: text[0..8000]  # Truncate to avoid limits
      })
      
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(request)
      end
      
      return nil unless response.code == "200"
      
      JSON.parse(response.body).dig("data", 0, "embedding")
    rescue => e
      Log.warn("OpenAI embedding failed", error: e.message) if defined?(Log)
      nil
    end

    def embed_ollama(text)
      require "net/http"
      require "json"
      
      uri = URI("http://localhost:11434/api/embeddings")
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = JSON.generate({
        model: "nomic-embed-text",
        prompt: text[0..8000]
      })
      
      response = Net::HTTP.start(uri.hostname, uri.port) do |http|
        http.request(request)
      end
      
      return nil unless response.code == "200"
      
      JSON.parse(response.body)["embedding"]
    rescue => e
      Log.warn("Ollama embedding failed", error: e.message) if defined?(Log)
      nil
    end

    def semantic_search(query, k: 5, rerank: false)
      query_vec = embed(query)
      return keyword_search(query, k: k) unless query_vec

      results = @chunks.map do |chunk|
        vec = @embeddings[chunk[:id]]
        next unless vec
        
        score = cosine_similarity(query_vec, vec)
        { chunk: chunk, score: score, rank_source: :semantic }
      end.compact

      results.sort_by! { |r| -r[:score] }
      results.first(k)
    end

    def keyword_search(query, k: 5)
      query_terms = query.downcase.split(/\W+/).reject { |t| t.length < 3 }
      return [] if query_terms.empty?

      results = @chunks.map do |chunk|
        text_lower = chunk[:text].downcase
        
        # TF-IDF-like scoring
        score = query_terms.sum do |term|
          count = text_lower.scan(/\b#{Regexp.escape(term)}\b/).size
          count > 0 ? Math.log(1 + count) : 0
        end
        
        { chunk: chunk, score: score, rank_source: :keyword }
      end

      results.select! { |r| r[:score] > 0 }
      results.sort_by! { |r| -r[:score] }
      results.first(k)
    end

    def simple_search(query, k: 5)
      query_lower = query.downcase
      
      results = @chunks.map do |chunk|
        text_lower = chunk[:text].downcase
        score = text_lower.include?(query_lower) ? 1.0 : 0.0
        
        { chunk: chunk, score: score, rank_source: :simple }
      end

      results.select! { |r| r[:score] > 0 }
      results.first(k)
    end

    def generate_query_variations(query)
      # Simple query variation generation
      variations = [query]
      
      # Add question forms
      unless query.start_with?("what", "how", "why", "when", "where", "who")
        variations << "What is #{query}?"
        variations << "How does #{query} work?"
      end
      
      # Add expanded form
      words = query.split(/\s+/)
      if words.length >= 2
        variations << words.join(" and ")
      end
      
      variations.uniq.first(3)  # Limit to avoid too many queries
    end

    def reciprocal_rank_fusion(results)
      k = @config[:rrf_k]
      chunk_scores = Hash.new(0)
      
      # Group by query
      results.group_by { |r| r[:chunk][:id] }.each do |chunk_id, chunk_results|
        chunk_results.each_with_index do |result, rank|
          chunk_scores[chunk_id] += 1.0 / (k + rank + 1)
        end
      end
      
      # Return sorted unique chunks
      chunk_scores.map do |chunk_id, fused_score|
        chunk = @chunks.find { |c| c[:id] == chunk_id }
        { chunk: chunk, score: fused_score, rank_source: :rrf }
      end.sort_by { |r| -r[:score] }
    end

    def rerank_results(query, results)
      # Simple cross-encoder-style reranking
      # In production, use a proper reranking model
      
      query_terms = query.downcase.split(/\W+/)
      
      results.map do |result|
        text = result[:chunk][:text].downcase
        
        # Position-aware scoring
        position_score = query_terms.map do |term|
          pos = text.index(term)
          pos ? 1.0 / (1 + pos / 100.0) : 0
        end.sum
        
        # Combine with original score
        rerank_score = result[:score] * 0.7 + position_score * 0.3
        
        result.merge(score: rerank_score, rank_source: :reranked)
      end.sort_by { |r| -r[:score] }
    end

    def repack_context(results)
      # Deduplicate and organize chunks
      seen_texts = Set.new
      unique_results = []
      
      results.each do |result|
        text = result[:chunk][:text]
        normalized = text.gsub(/\s+/, " ").strip
        
        unless seen_texts.include?(normalized)
          seen_texts << normalized
          unique_results << result
        end
      end
      
      # Sort by source and index for coherent reading
      unique_results.sort_by! do |r|
        [r[:chunk][:source] || "", r[:chunk][:idx] || 0]
      end
      
      # Format context
      unique_results.map.with_index do |result, idx|
        source = result[:chunk][:source] ? " [#{File.basename(result[:chunk][:source])}]" : ""
        "[#{idx + 1}]#{source}\n#{result[:chunk][:text]}"
      end.join("\n\n---\n\n")
    end

    def cosine_similarity(vec_a, vec_b)
      return 0 unless vec_a && vec_b
      return 0 if vec_a.empty? || vec_b.empty?
      
      dot_product = vec_a.zip(vec_b).sum { |a, b| a * b }
      magnitude_a = Math.sqrt(vec_a.sum { |a| a * a })
      magnitude_b = Math.sqrt(vec_b.sum { |b| b * b })
      
      return 0 if magnitude_a == 0 || magnitude_b == 0
      
      dot_product / (magnitude_a * magnitude_b)
    rescue => e
      Log.warn("Cosine similarity error", error: e.message) if defined?(Log)
      0
    end

    def update_stats
      @stats[:chunks] = @chunks.size
      @stats[:embeddings] = @embeddings.size
    end
  end
end
