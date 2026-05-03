# frozen_string_literal: true

require "json"

module Master
  class Learnings
    STORE_PATH = "data/learnings.jsonl".freeze
    MAX_ENTRIES = 500
    CONFIDENCE_DECAY_DAYS = 30

    def initialize(root:)
      @path = File.join(root, STORE_PATH)
      @entries = load_entries
    end

    def record(trigger:, strategy:, outcome:)
      existing = @entries.find { |e| e["trigger"] == trigger.to_s && e["strategy"] == strategy.to_s }
      if existing
        existing["reuse_count"] = existing["reuse_count"].to_i + 1
        existing["confidence"]  = [existing["confidence"].to_f + 0.05, 1.0].min
        existing["outcome"]     = outcome.to_s
        existing["timestamp"]   = Time.now.to_i
      else
        @entries << {
          "trigger"     => trigger.to_s,
          "strategy"    => strategy.to_s,
          "outcome"     => outcome.to_s,
          "confidence"  => outcome == :fixed ? 0.7 : 0.4,
          "reuse_count" => 0,
          "timestamp"   => Time.now.to_i
        }
      end
      prune_old!
      persist
    end

    def search(trigger_fragment, limit: 3)
      fragment = trigger_fragment.to_s.downcase
      @entries
        .select { |e| e["trigger"].to_s.downcase.include?(fragment) && e["outcome"] != "failed" }
        .sort_by { |e| -e["confidence"].to_f }
        .first(limit)
    end

    def all = @entries.dup

    def prune_stale!
      cutoff = Time.now.to_i - (CONFIDENCE_DECAY_DAYS * 86_400)
      before = @entries.size
      @entries.reject! { |e| e["reuse_count"].to_i == 0 && e["timestamp"].to_i < cutoff }
      persist if @entries.size < before
    end

    private

    def load_entries
      return [] unless File.exist?(@path)
      File.readlines(@path, chomp: true)
          .map { |l| begin; JSON.parse(l); rescue StandardError => _e; nil; end }
          .compact
    rescue StandardError => _e
      []
    end

    def persist
      FileUtils.mkdir_p(File.dirname(@path))
      tmp_path = "#{@path}.tmp"
      File.write(tmp_path, @entries.map { |e| JSON.generate(e) }.join("\n") + "\n")
      File.rename(tmp_path, @path)
    end

    def prune_old!
      @entries = @entries.last(MAX_ENTRIES) if @entries.size > MAX_ENTRIES
    end
  end
end
