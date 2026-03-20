# frozen_string_literal: true

require "yaml"
require "fileutils"

module Master
  # Persistent cross-session memory store with TF-IDF semantic search.
  # Stored at .master/memory.yml — survives restarts.
  class Memory
    def initialize(root: Dir.pwd)
      @path  = File.join(root, ".master", "memory.yml")
      @store = load_store
    end

    def remember(key, value)
      @store[key.to_s] = { "value" => value.to_s, "ts" => Time.now.to_i }
      persist
    end

    # Keys are always stored and retrieved as strings.
    def recall(key)
      @store.dig(key.to_s, "value")
    end

    def forget(key)
      @store.delete(key.to_s)
      persist
    end

    def all = @store.transform_values { |v| v.is_a?(Hash) ? v["value"] : v }

    # Returns a compact string suitable for injection into system prompts.
    def context_summary
      return nil if @store.empty?
      lines = @store.map { |k, v| "- #{k}: #{v.is_a?(Hash) ? v["value"] : v}" }
      "Memory:\n#{lines.join("\n")}"
    end

    # TF-IDF ranked search across all memory entries.
    # Returns array of {key:, value:, score:} hashes, highest score first.
    def semantic_recall(query, top_n: 3)
      return [] if @store.empty?

      query_terms = tokenize(query)
      return [] if query_terms.empty?

      scored = @store.filter_map do |key, data|
        value = data.is_a?(Hash) ? data["value"].to_s : data.to_s
        doc   = "#{key} #{value}"
        score = tfidf_score(query_terms, tokenize(doc))
        next if score.zero?
        { key: key, value: value, score: score }
      end

      scored.sort_by { |e| -e[:score] }.first(top_n)
    end

    private

    def load_store
      return {} unless File.exist?(@path)
      YAML.safe_load_file(@path, symbolize_names: false) || {}
    rescue StandardError
      {}
    end

    def persist
      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, @store.to_yaml)
    end

    def tokenize(text)
      text.downcase.scan(/\b[a-z]{2,}\b/)
    end

    # Log-weighted term frequency similarity — no external gem required.
    def tfidf_score(query_terms, doc_terms)
      return 0.0 if doc_terms.empty?
      freq = doc_terms.tally
      query_terms.sum { |t| Math.log(1.0 + freq.fetch(t, 0).to_f) }
    end
  end
end
