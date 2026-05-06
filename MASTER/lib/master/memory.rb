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

    include Search

    def initialize(root: Dir.pwd)
      @path  = File.join(root, ".master", "memory.yml")
      @mutex = Mutex.new
      @store = load_store
    end

    def remember(key, value)
      @mutex.synchronize do
        prune_stale! if @store.size > CONSOLIDATE_THRESHOLD
        @store[key.to_s] = { "value" => value.to_s, "ts" => Time.now.to_i }
        persist
      end
    end

    def recall(key)
      @store.dig(key.to_s, "value")
    end

    def forget(key)
      @mutex.synchronize { @store.delete(key.to_s); persist }
    end

    def all = @store.transform_values { |v| v.is_a?(Hash) ? v["value"] : v }

    # Token-limited injection for system prompt. Caps at MAX_INJECT_TOKENS.
    def context_summary
      active = @store.reject { |k, _| k.to_s.start_with?("archive/") || k == "_consolidated_summary" }
      return if active.empty?

      recent    = active.sort_by { |_, v| -(v.is_a?(Hash) ? v["ts"].to_i : 0) }.first(MAX_INJECT_ENTRIES)
      lines     = []
      token_sum = 0

      recent.each do |k, v|
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
