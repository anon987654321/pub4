# frozen_string_literal: true

require "yaml"
require "fileutils"

module Master
  class Memory
    def initialize(root: Dir.pwd)
      @persistence = MemoryPersistence.new(root)
      @search = MemorySearch.new(@persistence.store)
    end

    def remember(key, value)
      @persistence.remember(key, value)
    end

    def recall(key)
      @persistence.recall(key)
    end

    def forget(key)
      @persistence.forget(key)
    end

    def all
      @persistence.all
    end

    def context_summary
      @persistence.context_summary
    end

    def semantic_recall(query, top_n: 3)
      @search.semantic_recall(query, top_n: top_n)
    end
  end

  class MemoryPersistence
    attr_reader :store

    def initialize(root: Dir.pwd)
      @path = File.join(root, ".master", "memory.yml")
      @store = load_store
    end

    def remember(key, value)
      @store[key.to_s] = { "value" => value.to_s, "ts" => Time.now.to_i }
      persist
    end

    def recall(key)
      @store.dig(key.to_s, "value")
    end

    def forget(key)
      @store.delete(key.to_s)
      persist
    end

    def all
      @store.transform_values { |v| v.is_a?(Hash) ? v["value"] : v }
    end

    def context_summary
      return nil if @store.empty?
      lines = @store.map { |k, v| "- #{k}: #{v.is_a?(Hash) ? v["value"] : v}" }
      "Memory:\n#{lines.join("\n")}"
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
  end

  class MemorySearch
    def initialize(store)
      @store = store
    end

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

    def tokenize(text)
      text.downcase.scan(/\b[a-z]{2,}\b/)
    end

    def tfidf_score(query_terms, doc_terms)
      return 0.0 if doc_terms.empty?
      freq = doc_terms.tally
      query_terms.sum { |t| Math.log(1.0 + freq.fetch(t, 0).to_f) }
    end
  end
end