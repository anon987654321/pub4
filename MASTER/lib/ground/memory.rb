# frozen_string_literal: true

require "yaml"
require "fileutils"

module Master
  module Ground
  # Memory — persistent cross-session store with TF-IDF semantic search.
  class Memory
    module Search
      def semantic_recall(query, top_n: 3)
        store_snap = @mutex.synchronize { @store.dup }
        return [] if store_snap.empty?
        if Judge::Embeddings.enabled? && (qvec = Judge::Embeddings.embed(query))
          hits = vector_recall(qvec, top_n, store_snap)
          return hits unless hits.empty?
        end
        tfidf_recall(query, top_n, store_snap)
      end

      private

      def vector_recall(qvec, top_n, store)
        store.filter_map do |key, data|
          next unless data.is_a?(Hash) && data["vec"].is_a?(Array)
          score = Judge::Embeddings.cosine(qvec, data["vec"])
          next if score < Judge::Embeddings::MIN_SIM
          { key: key, value: data["value"].to_s, score: score }
        end.sort_by { |e| -e[:score] }.first(top_n)
      end

      def tfidf_recall(query, top_n, store)
        terms = tokenize(query)
        return [] if terms.empty?
        store.filter_map { |key, data|
          value = data.is_a?(Hash) ? data["value"].to_s : data.to_s
          score = tfidf_score(terms, tokenize("#{key} #{value}"))
          next if score.zero?
          { key: key, value: value, score: score }
        }.sort_by { |e| -e[:score] }.first(top_n)
      end

      def tokenize(text) = text.downcase.scan(/\b[a-z]{2,}\b/)

      def tfidf_score(query_terms, doc_terms)
        return 0.0 if doc_terms.empty?
        freq = doc_terms.tally
        query_terms.sum { |t| Math.log(1.0 + freq.fetch(t, 0).to_f) }
      end
    end
    TTL_DAYS = 90
    CONSOLIDATE_THRESHOLD = 40
    SECONDS_PER_DAY = 86_400
    MAX_INJECT_TOKENS = 2000
    MAX_INJECT_ENTRIES = 5
    TYPES = %w[user feedback project reference general].freeze
    AUTO_SAVE_PATTERNS = {
      "user" => /\b(?:i'?m a|i am a|my role is|i work as)\s+([^.,;\n]{3,80})/i,
      "feedback" => /\b(?:don'?t|stop|never|always|prefer|from now on)\s+([^.,;\n]{3,120})/i,
      "project" => /\b(?:we'?re|deadline|launching|deploying|migrating)\s+([^.,;\n]{3,120})/i
    }.freeze

    include Search
    include AtomicWrite

    def initialize(root: Dir.pwd)
      @root = root
      @path = File.join(root, ".master", "memory.yml")
      @mutex = Mutex.new
      @store = load_store
      import_external!
    end

    def remember(key, value, type: "general")
      type = TYPES.include?(type.to_s) ? type.to_s : "general"
      @mutex.synchronize do
        prune_stale! if @store.size > CONSOLIDATE_THRESHOLD
        entry = { "value" => value.to_s, "ts" => Time.now.to_i, "type" => type }
        if (vec = Judge::Embeddings.embed("#{key} #{value}"))
          entry["vec"] = vec
        end
        @store[key.to_s] = entry
        persist
      end
    end

    def by_type(type)
      @mutex.synchronize do
        @store.select { |k, v| v.is_a?(Hash) && v["type"] == type.to_s && !k.start_with?("archive/") }
      end
    end

    def type_counts
      @mutex.synchronize do
        counts = Hash.new(0)
        @store.each do |k, v|
          next if k.start_with?("archive/") || k == "_consolidated_summary"
          counts[v.is_a?(Hash) ? (v["type"] || "general") : "general"] += 1
        end
        counts
      end
    end

    def auto_save(text)
      return if text.to_s.empty?
      AUTO_SAVE_PATTERNS.each do |type, re|
        next unless (m = text.match(re))
        snippet = m[1].strip
        next if snippet.length < 3
        n = @mutex.synchronize { @store.keys.count { |k| k.start_with?("auto/#{type}/") } } + 1
        key = "auto/#{type}/#{n}"
        remember(key, snippet, type: type)
        return key
      end
      nil
    end

    def recall(key)
      @mutex.synchronize { @store.dig(key.to_s, "value") }
    end

    def forget(key)
      @mutex.synchronize { @store.delete(key.to_s); persist }
    end

    def all = @mutex.synchronize { @store.transform_values { |v| v.is_a?(Hash) ? v["value"] : v } }

    def context_summary
      active = @mutex.synchronize do
        @store.reject { |k, _| k.to_s.start_with?("archive/") || k == "_consolidated_summary" }
      end
      return if active.empty?

      grouped = active.group_by { |_, v| v.is_a?(Hash) ? (v["type"] || "general") : "general" }
      ordered = TYPES.flat_map { |t|
        (grouped[t] || []).sort_by { |_, v| -(v.is_a?(Hash) ? v["ts"].to_i : 0) }
      }.first(MAX_INJECT_ENTRIES * 2)
      lines, token_sum, current_type = [], 0, nil

      ordered.each do |k, v|
        type = v.is_a?(Hash) ? (v["type"] || "general") : "general"
        if type != current_type
          lines << "[#{type}]"
          current_type = type
        end
        text = "- #{k}: #{v.is_a?(Hash) ? v["value"] : v}"
        est = text.bytesize / Master::Trace::Session::TOKENS_PER_CHAR
        break if token_sum + est > MAX_INJECT_TOKENS
        lines << text
        token_sum += est
      end
      return if lines.empty?

      archived_n = @mutex.synchronize { @store.count { |k, _| k.to_s.start_with?("archive/") } }
      summary = recall("_consolidated_summary")
      header = summary ? "Memory (#{summary.to_s[0, 80]}):" : "Memory:"
      header += " [+#{archived_n} archived]" if archived_n > 0
      "#{header}\n#{lines.join("\n")}"
    end

    def consolidate!(agent: nil)
      return "nothing to consolidate" if @store.empty?

      now = Time.now.to_i
      entries = nil
      archived = 0

      @mutex.synchronize do
        entries = @store.reject { |k, _| k.to_s.start_with?("archive/") }
        scored = entries.map do |key, data|
          ts = data.is_a?(Hash) ? data["ts"].to_i : 0
          age_d = (now - ts) / 86_400.0
          { key: key, score: 1.0 / (1.0 + age_d / TTL_DAYS.to_f) }
        end
        scored.each do |entry|
          next if entry[:key] == "_consolidated_summary"
          next unless entry[:score] < 0.33
          @store["archive/#{entry[:key]}"] = @store.delete(entry[:key])
          archived += 1
        end
        persist
      end

      summarize_active_entries(agent) if agent
      "dreaming: #{entries.size} entries checked, #{archived} archived"
    rescue StandardError => e
      "consolidation error: #{e.message}"
    end

    private

    # Ask the agent to produce a two-sentence summary of current active entries,
    # then store it as the consolidated summary key.
    def summarize_active_entries(agent)
      active_text = @mutex.synchronize do
        @store
          .reject { |k, _| k.to_s.start_with?("archive/") || k == "_consolidated_summary" }
          .map { |k, v| "#{k}: #{v.is_a?(Hash) ? v["value"] : v}" }
          .join("\n")
      end
      return if active_text.strip.empty?
      summary = agent.ask_once("Summarize in 2 concise sentences, preserving all key facts:\n#{active_text}")
      remember("_consolidated_summary", summary.strip)
    end

    # Imports markdown memory files from data/claude/ on first boot.
    def import_external!
      dir = File.join(@root, "data", "claude")
      return unless Dir.exist?(dir)
      Dir.glob(File.join(dir, "*.md")).each do |path|
        next if File.basename(path) == "MEMORY.md"
        key = "claude/#{File.basename(path, ".md")}"
        next if @store.key?(key)
        type, body = parse_frontmatter(path)
        next if body.empty?
        remember(key, body, type: type)
      end
    rescue StandardError => e
      Master::Ground::Swallow.log(e, context: "memory.preload_claude_md")
    end

    def parse_frontmatter(path)
      fm = Master::Ground::Frontmatter.parse_file(path)
      type = fm[:meta]["type"].to_s
      type = "general" if type.empty?
      [type, fm[:body]]
    end

    def prune_stale!
      cutoff = Time.now.to_i - TTL_DAYS * SECONDS_PER_DAY
      @store.each do |k, v|
        next if k.to_s.start_with?("archive/") || k == "_consolidated_summary"
        ts = v.is_a?(Hash) ? v["ts"].to_i : 0
        next unless ts > 0 && ts < cutoff
        @store["archive/#{k}"] = @store.delete(k)
      end
    end

    def load_store
      return {} unless File.exist?(@path)
      loaded = Master.load_yaml(@path)
      loaded.is_a?(Hash) ? loaded : {}
    rescue StandardError => e
      Master::Ground::Swallow.log(e, context: "memory.load_store", path: @path)
      {}
    end

    def persist
      FileUtils.mkdir_p(File.dirname(@path))
      write_atomic(@path, @store.to_yaml)
    end

  end
  end
end
