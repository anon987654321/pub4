# frozen_string_literal: true

module MASTER
  # LearningFeedback - Pattern extraction from successful repairs
  # Stores repair patterns in DB so future identical findings bypass the LLM
  # Tracks success/fail counts per pattern
  module LearningFeedback
    extend self

    def file_path
      if defined?(Paths)
        File.join(Paths.var, "repair_patterns.jsonl")
      else
        File.join(MASTER.root, "memory", "repair_patterns.jsonl")
      end
    end

    def record_pattern(finding_type:, pattern:, fix:, context: {})
      record = {
        id: generate_id,
        finding_type: finding_type,
        pattern: pattern,
        fix: fix,
        context: context,
        created_at: Time.now.utc.iso8601,
        success_count: 0,
        fail_count: 0,
        last_applied: nil,
      }

      ensure_file_exists
      File.open(file_path, "a") { |f| f.puts(JSON.generate(record)) }

      Result.ok(pattern_id: record[:id])
    rescue StandardError => e
      Result.err("Failed to record pattern: #{e.message}")
    end

    def find_pattern(finding_type:, code_context: nil)
      patterns = all_patterns.select { |p| p[:finding_type] == finding_type }

      return nil if patterns.empty?

      # Find best matching pattern
      if code_context
        patterns.select! { |p| matches_context?(p, code_context) }
      end

      # Sort by success rate
      patterns.sort_by! do |p|
        total = p[:success_count] + p[:fail_count]
        total.zero? ? 0 : p[:success_count].to_f / total
      end

      patterns.last # Highest success rate
    end

    def record_success(pattern_id)
      update_pattern_stats(pattern_id, :success)
    end

    def record_failure(pattern_id)
      update_pattern_stats(pattern_id, :fail)
    end

    def all_patterns
      return [] unless File.exist?(file_path)

      File.readlines(file_path).filter_map do |line|
        JSON.parse(line.strip, symbolize_names: true)
      rescue JSON::ParserError
        nil
      end
    end

    def by_type(finding_type)
      all_patterns.select { |p| p[:finding_type] == finding_type }
    end

    def stats
      patterns = all_patterns
      total_count = patterns.size
      total_applications = patterns.sum { |p| p[:success_count] + p[:fail_count] }
      total_successes = patterns.sum { |p| p[:success_count] }

      {
        total_patterns: total_count,
        total_applications: total_applications,
        total_successes: total_successes,
        success_rate: total_applications.zero? ? 0.0 : (total_successes.to_f / total_applications * 100).round(2),
      }
    end

    def quality_tiers
      return {} unless defined?(MASTER::LearningQuality)

      patterns = all_patterns
      tiers = { promote: [], keep: [], demote: [], retire: [] }

      patterns.each do |pattern|
        tier = LearningQuality.evaluate_pattern(pattern)
        tiers[tier] << pattern[:id] if tier
      end

      tiers
    end

    def prune_retired
      return Result.err("LearningQuality not available") unless defined?(MASTER::LearningQuality)

      patterns = all_patterns
      retired = patterns.select { |p| LearningQuality.evaluate_pattern(p) == :retire }

      if retired.any?
        active_patterns = patterns.reject { |p| retired.include?(p) }
        rewrite(active_patterns)
        Result.ok(pruned: retired.size)
      else
        Result.ok(pruned: 0)
      end
    rescue StandardError => e
      Result.err("Failed to prune patterns: #{e.message}")
    end

    private

    def generate_id
      require "securerandom" unless defined?(SecureRandom)
      SecureRandom.hex(8)
    end

    def ensure_file_exists
      dir = File.dirname(file_path)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
    end

    def matches_context?(pattern, code_context)
      # Simple context matching - could be more sophisticated
      return true unless pattern[:context] && pattern[:context].any?

      pattern[:context].any? do |key, value|
        code_context[key] == value
      end
    end

    def update_pattern_stats(pattern_id, outcome)
      patterns = all_patterns
      pattern = patterns.find { |p| p[:id] == pattern_id }
      return Result.err("Pattern not found: #{pattern_id}") unless pattern

      if outcome == :success
        pattern[:success_count] += 1
      else
        pattern[:fail_count] += 1
      end

      pattern[:last_applied] = Time.now.utc.iso8601

      rewrite(patterns)
      Result.ok(pattern: pattern)
    rescue StandardError => e
      Result.err("Failed to update pattern stats: #{e.message}")
    end

    def rewrite(patterns)
      ensure_file_exists
      File.open(file_path, "w") do |f|
        patterns.each { |p| f.puts(JSON.generate(p)) }
      end
    end
  end
end
