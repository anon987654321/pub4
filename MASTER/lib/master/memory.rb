# frozen_string_literal: true

require "yaml"
require "fileutils"

require_relative "memory/search"

module Master
  # Memory — persistent cross-session store with TF-IDF semantic search.
  # Stored at .master/memory.yml. Survives restarts.
  class Memory
    TTL_DAYS = 90
    CONSOLIDATE_THRESHOLD = 40
    SECONDS_PER_DAY = 86_400
    MAX_INJECT_TOKENS = 2000
    MAX_INJECT_ENTRIES = 5
    TYPES = %w[user feedback project reference general].freeze
    AUTO_SAVE_PATTERNS = {
      "user"     => /\b(?:i'?m a|i am a|my role is|i work as)\s+([^.,;\n]{3,80})/i,
      "feedback" => /\b(?:don'?t|stop|never|always|prefer|from now on)\s+([^.,;\n]{3,120})/i,
      "project"  => /\b(?:we'?re|deadline|launching|deploying|migrating)\s+([^.,;\n]{3,120})/i
    }.freeze

    include Search

    def initialize(root: Dir.pwd)
      @root  = root
      @path  = File.join(root, ".master", "memory.yml")
      @mutex = Mutex.new
      @store = load_store
      import_external!
    end

    def remember(key, value, type: "general")
      type = TYPES.include?(type.to_s) ? type.to_s : "general"
      @mutex.synchronize do
        prune_stale! if @store.size > CONSOLIDATE_THRESHOLD
        entry = { "value" => value.to_s, "ts" => Time.now.to_i, "type" => type }
        if (vec = Embeddings.embed("#{key} #{value}"))
          entry["vec"] = vec
        end
        @store[key.to_s] = entry
        persist
      end
    end

    def by_type(type)
      @store.select { |k, v| v.is_a?(Hash) && v["type"] == type.to_s && !k.start_with?("archive/") }
    end

    def type_counts
      counts = Hash.new(0)
      @store.each do |k, v|
        next if k.start_with?("archive/") || k == "_consolidated_summary"
        counts[v.is_a?(Hash) ? (v["type"] || "general") : "general"] += 1
      end
      counts
    end

    # Heuristic auto-save. Scans text for first matching pattern; saves under "auto/<type>/<n>".
    # Returns saved key or nil.
    def auto_save(text)
      return if text.to_s.empty?
      AUTO_SAVE_PATTERNS.each do |type, re|
        next unless (m = text.match(re))
        snippet = m[1].strip
        next if snippet.length < 3
        n   = @store.keys.count { |k| k.start_with?("auto/#{type}/") } + 1
        key = "auto/#{type}/#{n}"
        remember(key, snippet, type: type)
        return key
      end
      nil
    end

    def recall(key)
      @store.dig(key.to_s, "value")
    end

    def forget(key)
      @mutex.synchronize { @store.delete(key.to_s); persist }
    end

    def all = @store.transform_values { |v| v.is_a?(Hash) ? v["value"] : v }

    # Token-limited injection for system prompt. Groups by type, caps at MAX_INJECT_TOKENS.
    def context_summary
      active = @store.reject { |k, _| k.to_s.start_with?("archive/") || k == "_consolidated_summary" }
      return if active.empty?

      grouped = active.group_by { |_, v| v.is_a?(Hash) ? (v["type"] || "general") : "general" }
      ordered = TYPES.flat_map { |t| (grouped[t] || []).sort_by { |_, v| -(v.is_a?(Hash) ? v["ts"].to_i : 0) } }
                     .first(MAX_INJECT_ENTRIES * 2)
      lines, token_sum, current_type = [], 0, nil

      ordered.each do |k, v|
        type = v.is_a?(Hash) ? (v["type"] || "general") : "general"
        if type != current_type
          lines << "[#{type}]"
          current_type = type
        end
        text = "- #{k}: #{v.is_a?(Hash) ? v["value"] : v}"
        est  = text.bytesize / Session::TOKENS_PER_CHAR
        break if token_sum + est > MAX_INJECT_TOKENS
        lines << text
        token_sum += est
      end
      return if lines.empty?

      archived_n = @store.count { |k, _| k.to_s.start_with?("archive/") }
      summary    = recall("_consolidated_summary")
      header     = summary ? "Memory (#{summary.to_s[0, 80]}):" : "Memory:"
      header    += " [+#{archived_n} archived]" if archived_n > 0
      "#{header}\n#{lines.join("\n")}"
    end

    # Three-phase consolidation: light (score), deep (archive), REM (LLM summary).
    def consolidate!(agent: nil)
      return "nothing to consolidate" if @store.empty?

      now = Time.now.to_i
      entries = nil
      archived = 0

      @mutex.synchronize do
        entries = @store.reject { |k, _| k.to_s.start_with?("archive/") }
        scored  = entries.map do |key, data|
          ts    = data.is_a?(Hash) ? data["ts"].to_i : 0
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

      if agent
        active_text = @mutex.synchronize do
          @store
            .reject { |k, _| k.to_s.start_with?("archive/") || k == "_consolidated_summary" }
            .map    { |k, v| "#{k}: #{v.is_a?(Hash) ? v["value"] : v}" }
            .join("\n")
        end
        unless active_text.strip.empty?
          summary = agent.ask_once("Summarize in 2 concise sentences, preserving all key facts:\n#{active_text}")
          remember("_consolidated_summary", summary.strip)
        end
      end

      "dreaming: #{entries.size} entries checked, #{archived} archived"
    rescue StandardError => e
      "consolidation error: #{e.message}"
    end

    private

    # Imports markdown memory files from data/claude/ on first boot.
    # Each file's frontmatter type maps to MASTER's memory type; body becomes the value.
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
    rescue StandardError
      nil
    end

    def parse_frontmatter(path)
      raw = File.read(path, encoding: "UTF-8")
      m = raw.match(/\A---\n(.*?)\n---\n(.*)/m)
      return ["general", raw.strip] unless m
      meta = YAML.safe_load(m[1]) || {}
      [meta["type"].to_s, m[2].strip]
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
    rescue StandardError => _e
      {}
    end

    def persist
      dir = File.dirname(@path)
      FileUtils.mkdir_p(dir)
      tmp = "#{@path}.tmp.#{Process.pid}"
      File.write(tmp, @store.to_yaml)
      File.rename(tmp, @path)
    rescue StandardError => e
      File.delete(tmp) if defined?(tmp) && File.exist?(tmp) rescue nil
      raise e
    end

  end
end
