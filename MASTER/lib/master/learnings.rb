# frozen_string_literal: true

require "json"

module Master
  # Append-only ledger for autoloop strategy outcomes and RSI feedback events.
  # RSI (Recursive Self-Improvement) pattern from OpenCrabs: dimensional statistics
  # with time windows drive three-category opportunity detection.
  class Learnings
    STORE_PATH           = "data/learnings.jsonl".freeze
    EVENTS_PATH          = "data/feedback_ledger.jsonl".freeze
    MAX_ENTRIES          = 500
    MAX_EVENTS           = 2000
    CONFIDENCE_DECAY_DAYS = 30

    RSI_WINDOW_DAYS      = 7
    RSI_FAIL_THRESHOLD   = 0.20   # >20% failure rate triggers opportunity
    RSI_CORRECTION_MIN   = 3      # ≥3 user corrections triggers opportunity
    RSI_PROVIDER_MIN     = 3      # ≥3 provider errors triggers opportunity

    def initialize(root:)
      @path        = File.join(root, STORE_PATH)
      @events_path = File.join(root, EVENTS_PATH)
      @mutex       = Mutex.new
      @entries     = load_entries
      @events      = load_events
    end

    # Strategy ledger — autoloop fix records
    def record(trigger:, strategy:, outcome:)
      @mutex.synchronize do
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
    end

    def search(trigger_fragment, limit: 3)
      fragment = trigger_fragment.to_s.downcase
      @mutex.synchronize do
        @entries
          .select { |e| e["trigger"].to_s.downcase.include?(fragment) && e["outcome"] != "failed" }
          .sort_by { |e| -e["confidence"].to_f }
          .first(limit)
      end
    end

    def all = @mutex.synchronize { @entries.dup }

    # RSI feedback ledger — append-only event recording
    def record_event(event_type:, dimension:, value: nil, metadata: nil)
      event = {
        "event_type" => event_type.to_s,
        "dimension"  => dimension.to_s,
        "value"      => value,
        "metadata"   => metadata,
        "ts"         => Time.now.to_i
      }.compact
      @mutex.synchronize do
        @events << event
        @events = @events.last(MAX_EVENTS) if @events.size > MAX_EVENTS
        persist_events
      end
    end

    # Returns {success: N, failure: N, fail_rate: f} for dimension value within window.
    def stats_by_dimension(dimension, since: nil)
      cutoff = since || (Time.now.to_i - (RSI_WINDOW_DAYS * 86_400))
      @mutex.synchronize do
        relevant = @events.select { |e|
          e["dimension"] == dimension.to_s && e["ts"].to_i >= cutoff
        }
        by_type = relevant.group_by { |e| e["event_type"] }
        success = (by_type["tool_success"] || []).size
        failure = (by_type["tool_failure"] || []).size
        total   = success + failure
        { success:, failure:, total:, fail_rate: total.zero? ? 0.0 : (failure.to_f / total).round(3) }
      end
    end

    # RSI three-category opportunity detection (OpenCrabs pattern)
    def opportunities
      cutoff = Time.now.to_i - (RSI_WINDOW_DAYS * 86_400)
      @mutex.synchronize do
        recent = @events.select { |e| e["ts"].to_i >= cutoff }

        # Category 1: tools with high failure rate
        tool_events = recent.select { |e| %w[tool_success tool_failure].include?(e["event_type"]) }
        tool_stats  = tool_events.group_by { |e| e["dimension"] }.filter_map { |tool, evs|
          success = evs.count { |e| e["event_type"] == "tool_success" }
          failure = evs.count { |e| e["event_type"] == "tool_failure" }
          total   = success + failure
          rate    = total.zero? ? 0.0 : failure.to_f / total
          { category: :high_failure, dimension: tool, fail_rate: rate.round(3), 
total: } if rate >= RSI_FAIL_THRESHOLD && total >= 3
        }

        # Category 2: repeated user corrections
        corrections = recent.select { |e| e["event_type"] == "user_correction" }
                            .group_by { |e| e["dimension"] }
                            .filter_map { |dim, evs|
          { category: :repeated_correction, dimension: dim, count: evs.size } if evs.size >= RSI_CORRECTION_MIN
        }

        # Category 3: provider errors
        provider_errs = recent.select { |e| e["event_type"] == "provider_error" }
                              .group_by { |e| e["dimension"] }
                              .filter_map { |dim, evs|
          { category: :provider_errors, dimension: dim, count: evs.size } if evs.size >= RSI_PROVIDER_MIN
        }

        tool_stats + corrections + provider_errs
      end
    end

    def prune_stale!
      cutoff = Time.now.to_i - (CONFIDENCE_DECAY_DAYS * 86_400)
      @mutex.synchronize do
        before = @entries.size
        @entries.reject! { |e| e["reuse_count"].to_i == 0 && e["timestamp"].to_i < cutoff }
        persist if @entries.size < before
      end
    end

    private

    def load_entries
      return [] unless File.exist?(@path)
      File.readlines(@path, chomp: true).filter_map do |l|
        JSON.parse(l)
      rescue JSON::ParserError
        nil
      end
    rescue StandardError => _e
      []
    end

    def load_events
      return [] unless File.exist?(@events_path)
      File.readlines(@events_path, chomp: true).filter_map do |l|
        JSON.parse(l)
      rescue JSON::ParserError
        nil
      end
    rescue StandardError => _e
      []
    end

    def persist
      FileUtils.mkdir_p(File.dirname(@path))
      tmp_path = "#{@path}.tmp.#{Process.pid}"
      File.write(tmp_path, @entries.map { |e| JSON.generate(e) }.join("\n") + "\n")
      File.rename(tmp_path, @path)
    end

    def persist_events
      FileUtils.mkdir_p(File.dirname(@events_path))
      tmp_path = "#{@events_path}.tmp.#{Process.pid}"
      File.write(tmp_path, @events.map { |e| JSON.generate(e) }.join("\n") + "\n")
      File.rename(tmp_path, @events_path)
    end

    def prune_old!
      @entries = @entries.last(MAX_ENTRIES) if @entries.size > MAX_ENTRIES
    end
  end
end
