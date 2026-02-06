# frozen_string_literal: true

require_relative 'weaviate'
require 'json'
require 'time'

module MASTER
  # Original simple memory for sessions
  module Memory
    HISTORY_THRESHOLD = 10
    HISTORY_HEAD = 2
    HISTORY_TAIL = 8

    @sessions = {}

    class << self
      def store(key, value)
        @sessions[key] = value
      end

      def fetch(key)
        @sessions[key]
      end

      def clear
        @sessions.clear
      end

      def compress(history, max_tokens: 4000)
        return history if history.size <= HISTORY_THRESHOLD

        # Keep first messages for context, last for recency
        history.first(HISTORY_HEAD) + history.last(HISTORY_TAIL)
      end

      def all
        @sessions.dup
      end

      def size
        @sessions.size
      end
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
