# frozen_string_literal: true

require "json"

module MASTER
  # Learnings - Captures insights from sessions for future use
  # When something is discovered (bug pattern, good practice, UX insight),
  # it gets recorded here so MASTER can apply it automatically next time
  module Learnings
    extend self

    CATEGORIES = %i[bug_pattern good_practice ux_insight architecture security].freeze

    QUALITY_TIERS = {
      promote: { min: 0.90, description: "Auto-apply (>90% success)" },
      keep: { min: 0.50, description: "Keep learning (50-90%)" },
      demote: { min: 0.20, description: "Needs review (20-50%)" },
      retire: { min: 0.00, description: "Remove (<20%)" }
    }.freeze

    MINIMUM_APPLICATIONS = 3
    MIN_CONFIDENCE = 0.6
    FEEDBACK_DB_FILE = "tmp/learning_feedback.jsonl"

    CONFIDENCE_WEIGHTS = {
      category: 0.3,
      success: 0.3,
      timestamp: 0.2,
      fix_hash: 0.2
    }.freeze

    def file_path
      File.join(Paths.var, "learnings.jsonl")
    end

    def record(category:, pattern:, description:, example: nil, severity: :info)
      raise ArgumentError, "Invalid category" unless CATEGORIES.include?(category)

      learning = {
        id: SecureRandom.hex(8),
        category: category,
        pattern: pattern,
        description: description,
        example: example,
        severity: severity,
        discovered_at: Time.now.utc.iso8601,
        applied_count: 0,
      }

      File.open(file_path, "a") { |f| f.puts(JSON.generate(learning)) }
      learning
    end

    def all
      return [] unless File.exist?(file_path)

      File.readlines(file_path).filter_map do |line|
        JSON.parse(line.strip, symbolize_names: true)
      rescue JSON::ParserError
        nil
      end
    end

    def by_category(category)
      all.select { |l| l[:category] == category }
    end

    def apply_to(code)
      learnings = by_category(:bug_pattern)
      issues = []

      learnings.each do |learning|
        next unless learning[:pattern]

        begin
          regex = Regexp.new(learning[:pattern])
          if code.match?(regex)
            issues << {
              learning_id: learning[:id],
              description: learning[:description],
              severity: learning[:severity],
            }
            increment_applied(learning[:id])
          end
        rescue RegexpError
          # Invalid pattern, skip
        end
      end

      issues
    end

    def increment_applied(id)
      learnings = all
      learning = learnings.find { |l| l[:id] == id }
      return unless learning

      learning[:applied_count] += 1
      rewrite(learnings)
    end

    # === Quality Assessment (from LearningQuality) ===

    def assess(learning)
      confidence = calculate_confidence(learning)
      {
        confidence: confidence,
        quality: confidence >= MIN_CONFIDENCE ? :acceptable : :low,
        usable: confidence >= MIN_CONFIDENCE
      }
    end
    def evaluate(pattern)
      return :unrated if pattern["applications"].to_i < MINIMUM_APPLICATIONS
      
      success_rate = calculate_success_rate(pattern)
      
      case success_rate
      when 0.90..1.0 then :promote
      when 0.50...0.90 then :keep
      when 0.20...0.50 then :demote
      else :retire
      end
    end

    def tier(pattern)
      evaluate(pattern)
    end

    def calculate_success_rate(pattern)
      if pattern.is_a?(Hash)
        successes = (pattern["successes"] || pattern[:successes] || 0).to_f
        failures = (pattern["failures"] || pattern[:failures] || 0).to_f
        total = successes + failures
        
        return 0.0 if total.zero?
        successes / total
      else
        0.0
      end
    end

    # === Feedback Recording (from LearningFeedback) ===

    def record_feedback(finding, fix, success:)
      ensure_feedback_db_exists
      
      pattern = {
        category: finding.category,
        message_pattern: generalize_message(finding.message),
        fix_hash: hash_fix(fix),
        success: success,
        timestamp: Time.now.to_i
      }
      
      File.open(feedback_db_path, "a") do |f|
        f.puts(pattern.to_json)
      end
      
      Result.ok
    rescue StandardError => e
      Result.err("Failed to record learning: #{e.message}")
    end

    def known_fix?(finding)
      patterns = load_feedback_patterns
      
      category_patterns = patterns.select do |p|
        p["category"] == finding.category.to_s
      end
      
      successes = category_patterns.count { |p| p["success"] }
      total = category_patterns.size
      
      total >= 3 && (successes.to_f / total) > 0.7
    end

    def apply_known(finding)
      patterns = load_feedback_patterns
      
      successful_patterns = patterns.select do |p|
        p["category"] == finding.category.to_s && p["success"]
      end
      
      return Result.err("No successful pattern found") if successful_patterns.empty?
      
      pattern = successful_patterns.last
      Result.ok(applied: pattern["fix_hash"])
    end

    def load_feedback_patterns
      return [] unless File.exist?(feedback_db_path)
      
      File.readlines(feedback_db_path).map do |line|
        JSON.parse(line.strip)
      rescue JSON::ParserError
        nil
      end.compact
    end

    # Prune retired patterns from database
    def prune!
      patterns = load_feedback_patterns
      
      grouped = patterns.group_by { |p| [p["category"], p["fix_hash"]] }
      
      pruned = 0
      kept_patterns = []
      
      grouped.each do |(_category, _hash), group|
        successes = group.count { |p| p["success"] }
        failures = group.count { |p| !p["success"] }
        applications = successes + failures
        
        next if applications < MINIMUM_APPLICATIONS
        
        aggregated = {
          "category" => group.first["category"],
          "fix_hash" => group.first["fix_hash"],
          "message_pattern" => group.first["message_pattern"],
          "successes" => successes,
          "failures" => failures,
          "applications" => applications
        }
        
        tier_result = evaluate(aggregated)
        
        if tier_result == :retire
          pruned += 1
        else
          kept_patterns << aggregated
        end
      end
      
      if pruned > 0
        File.open(feedback_db_path, "w") do |f|
          kept_patterns.each do |pattern|
            f.puts(pattern.to_json)
          end
        end
      end
      
      Result.ok(pruned: pruned, kept: kept_patterns.size)
    rescue StandardError => e
      Result.err("Failed to prune: #{e.message}")
    end

    def seed_from_session
      # Learnings discovered in the Feb 7 2026 deep analysis session
      [
        {
          category: :bug_pattern,
          pattern: 'DB\.setup(?!\s*\()',
          description: "DB.setup without MASTER:: prefix in bin/ scripts",
          example: "bin/master line 5: DB.setup should be MASTER::DB.setup",
          severity: :critical,
        },
        {
          category: :bug_pattern,
          pattern: '\.start_with\?\(["\']',
          description: "Calling .start_with? on value that might be a symbol",
          example: "SHORTCUTS[input] returns symbol, then .start_with? crashes",
          severity: :critical,
        },
        {
          category: :bug_pattern,
          pattern: '\.pop\(\d+\)(?!.*@dirty)',
          description: "Mutating collection without setting dirty flag",
          example: "session.history.pop(2) needs session.@dirty = true",
          severity: :major,
        },
        {
          category: :bug_pattern,
          pattern: '\["[a-z_]+"\]\s*\|\|\s*\[:[a-z_]+\]',
          description: "Mixed string/symbol hash access - use symbolize_names",
          example: 'row["model"] || row[:model] -> just use row[:model]',
          severity: :minor,
        },
        {
          category: :good_practice,
          pattern: "symbolize_names:\\s*true",
          description: "Always use symbolize_names: true with JSON.parse",
          severity: :info,
        },
        {
          category: :ux_insight,
          pattern: nil,
          description: "Show context % in prompt when > 5%",
          example: "master[strong|$9.50|ctx:12%]$",
          severity: :info,
        },
        {
          category: :ux_insight,
          pattern: nil,
          description: "Provide 'did you mean?' for typos within edit distance 2",
          severity: :info,
        },
        {
          category: :ux_insight,
          pattern: nil,
          description: "Auto-save session every 5 messages AND on Ctrl+C",
          severity: :info,
        },
        {
          category: :security,
          pattern: 'rm\s+-rf?\s+/',
          description: "Block destructive shell commands in Guard stage",
          severity: :critical,
        },
        {
          category: :architecture,
          pattern: nil,
          description: "Two session systems exist (Memory JSON, DB JSONL) - Session uses Memory",
          severity: :info,
        },
      ].each do |learning|
        record(**learning) unless exists?(learning[:description])
      end
    end
    
    
    # Extract regex pattern from code diff (simple heuristic)
    def self.extract_pattern_from_fix(original, fixed)
      # Find the line that changed
      original_lines = original.lines
      fixed_lines = fixed.lines
      
      # Handle length differences by iterating through the shorter array
      min_length = [original_lines.length, fixed_lines.length].min
      diff_line = nil
      
      min_length.times do |i|
        if original_lines[i] != fixed_lines[i]
          diff_line = [original_lines[i], fixed_lines[i]]
          break
        end
      end
      
      return nil unless diff_line
      
      original_part = diff_line[0]&.strip
      return nil unless original_part
      
      # Extract a simple regex pattern
      # Example: "foo.bar" becomes "foo\.bar"
      Regexp.escape(original_part[0..50]) # First 50 chars
    rescue StandardError
      nil
    end

    private

    def calculate_confidence(learning)
      return 0.0 unless learning.is_a?(Hash)
      
      score = 0.0
      score += CONFIDENCE_WEIGHTS[:category] if learning[:category]
      score += CONFIDENCE_WEIGHTS[:success] if learning[:success]
      score += CONFIDENCE_WEIGHTS[:timestamp] if learning[:timestamp]
      score += CONFIDENCE_WEIGHTS[:fix_hash] if learning[:fix_hash]
      score
    end

    def ensure_feedback_db_exists
      FileUtils.mkdir_p(File.dirname(feedback_db_path))
      FileUtils.touch(feedback_db_path) unless File.exist?(feedback_db_path)
    end

    def feedback_db_path
      File.join(MASTER.root, FEEDBACK_DB_FILE)
    end

    def generalize_message(message)
      message
        .gsub(/\d+/, "N")
        .gsub(/\/[^\s]+/, "PATH")
        .gsub(/'[^']+'/, "'X'")
    end

    def hash_fix(fix)
      if fix.is_a?(Hash)
        fix.hash.to_s
      elsif fix.respond_to?(:to_s)
        fix.to_s.hash.to_s
      else
        "unknown"
      end
    end

    def exists?(description)
      all.any? { |l| l[:description] == description }
    end

    def rewrite(learnings)
      File.open(file_path, "w") do |f|
        learnings.each { |l| f.puts(JSON.generate(l)) }
      end
    end
  end

  # Backward compatibility aliases
  module LearningQuality
    extend self

    MINIMUM_APPLICATIONS = Learnings::MINIMUM_APPLICATIONS
    MIN_CONFIDENCE = Learnings::MIN_CONFIDENCE
    
    TIERS = {
      promote: { threshold: 0.90, action: "Promote to core patterns" },
      keep: { threshold: 0.60, action: "Keep in active set" },
      demote: { threshold: 0.30, action: "Demote to experimental" },
      retire: { threshold: 0.0, action: "Retire pattern" }
    }.freeze

    def assess(learning)
      Learnings.assess(learning)
    end

    def evaluate(pattern)
      Learnings.evaluate(pattern)
    end

    def tier(pattern)
      Learnings.tier(pattern)
    end

    def calculate_success_rate(pattern)
      Learnings.calculate_success_rate(pattern)
    end
  end

  module LearningFeedback
    extend self

    DB_FILE = Learnings::FEEDBACK_DB_FILE

    def record(finding, fix, success:)
      Learnings.record_feedback(finding, fix, success: success)
    end

    def known_fix?(finding)
      Learnings.known_fix?(finding)
    end

    def apply_known(finding)
      Learnings.apply_known(finding)
    end

    def load_patterns
      Learnings.load_feedback_patterns
    end
  end
end
