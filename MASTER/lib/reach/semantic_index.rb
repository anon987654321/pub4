# frozen_string_literal: true

module Master
  module Reach
    # Fuzzy semantic cache: when SemanticCache's exact-key lookup misses, return a near-hit
    # whose prompt embedding is within a cosine threshold — ~31% of agent queries are
    # paraphrases of earlier ones. Pure Ruby over an injected embedder (Judge::Embeddings);
    # degrades to a no-op with embeddings off. Refs: semantic-similarity caching.
    class SemanticIndex
      DEFAULT_THRESHOLD = 0.92
      MAX_ENTRIES = 500

      def initialize(embedder:, threshold: DEFAULT_THRESHOLD, max_entries: MAX_ENTRIES)
        # responds to: enabled?, embed(text), cosine(a, b)
        @embedder = embedder
        @threshold = threshold
        @max_entries = max_entries
        # [{ embedding:, value: }, ...], oldest first
        @entries = []
      end

      # Value of the nearest stored entry within threshold, or nil on a miss.
      def nearest(text)
        vector = embed(text)
        return if vector.nil? || @entries.empty?

        value, score = best_match(vector)
        score && score >= @threshold ? value : nil
      end

      # Record a prompt's embedding -> value for future near-hits (oldest evicted past the cap).
      def remember(text, value)
        vector = embed(text)
        return value if vector.nil?

        @entries.push(embedding: vector, value: value)
        @entries.shift while @entries.size > @max_entries
        value
      end

      # Near-hit, or compute via the block and remember it.
      def fetch(text)
        hit = nearest(text)
        return hit unless hit.nil?

        remember(text, yield)
      end

      private

      def embed(text)
        return unless @embedder.enabled?

        @embedder.embed(text)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "SemanticIndex.embed")
        nil
      end

      def best_match(vector)
        @entries.map { |entry| [entry[:value], @embedder.cosine(vector, entry[:embedding])] }
                .max_by { |_value, score| score }
      end
    end
  end
end
