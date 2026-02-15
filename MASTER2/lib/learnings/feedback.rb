# frozen_string_literal: true

module MASTER
  # LearningFeedback - Pattern storage and retrieval for automated fixes
  module LearningFeedback
    extend self

    DB_FILE = "tmp/learning_feedback.jsonl"

    # Record a finding + fix pattern with success/fail
    def record(finding, fix, success:)
      ensure_db_exists

      pattern = {
        category: finding.category,
        message_pattern: generalize_message(finding.message),
        fix_hash: hash_fix(fix),
        success: success,
        timestamp: Time.now.to_i
      }

      # Append to JSONL
      File.open(db_path, "a") do |f|
        f.puts(pattern.to_json)
      end

      Result.ok
    rescue StandardError => e
      Result.err("Failed to record learning: #{e.message}")
    end

    # Check if we have a known successful fix for this finding
    def known_fix?(finding)
      patterns = load_patterns

      category_patterns = patterns.select do |p|
        p[:category] == finding.category.to_s
      end

      # Count successes
      successes = category_patterns.count { |p| p[:success] }
      total = category_patterns.size

      # Need at least 3 applications and >70% success rate
      total >= 3 && (successes.to_f / total) > 0.7
    end

    # Apply a known fix without LLM
    def apply_known(finding)
      patterns = load_patterns

      successful_patterns = patterns.select do |p|
        p[:category] == finding.category.to_s && p[:success]
      end

      return Result.err("No successful pattern found.") if successful_patterns.empty?

      # Use the most recent successful pattern
      pattern = successful_patterns.last

      # In a real system, this would reconstruct and apply the actual fix
      Result.ok(applied: pattern[:fix_hash])
    end

    def load_patterns
      return [] unless File.exist?(db_path)

      File.readlines(db_path).map do |line|
        JSON.parse(line.strip, symbolize_names: true)
      rescue JSON::ParserError
        nil
      end.compact
    end

    private

    def ensure_db_exists
      FileUtils.mkdir_p(File.dirname(db_path))
      FileUtils.touch(db_path) unless File.exist?(db_path)
    end

    def db_path
      File.join(MASTER.root, DB_FILE)
    end

    def generalize_message(message)
      # Remove specific numbers and paths to create pattern
      message
        .gsub(/\d+/, "N")
        .gsub(/\/[^\s]+/, "PATH")
        .gsub(/'[^']+'/, "'X'")
    end

    def hash_fix(fix)
      fix.to_s.hash.to_s
    end
  end
end
