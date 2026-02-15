# frozen_string_literal: true

module MASTER
  # Learnings - Captures insights from sessions for future use
  # When something is discovered (bug pattern, good practice, UX insight),
  # it gets recorded here so MASTER can apply it automatically next time
  module Learnings
    extend self

    CATEGORIES = %i[bug_pattern good_practice ux_insight architecture security].freeze

    # Quality tiers based on success rate (merged from LearningQuality)
    QUALITY_TIERS = {
      promote: { min: 0.90, description: "Auto-apply (>90% success)" },
      keep: { min: 0.50, description: "Keep learning (50-90%)" },
      demote: { min: 0.20, description: "Needs review (20-50%)" },
      retire: { min: 0.00, description: "Remove (<20%)" }
    }.freeze

    MINIMUM_APPLICATIONS = 3

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

    # Quality evaluation methods (merged from LearningQuality)
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
        successes = pattern["successes"].to_i
        failures = pattern["failures"].to_i
        total = successes + failures

        return 0.0 if total.zero?

        successes.to_f / total
      else
        0.0
      end
    end

    # Prune retired patterns from database
    def prune!
      return Result.err("LearningFeedback not available") unless defined?(LearningFeedback)

      patterns = LearningFeedback.load_patterns

      # Group by category and fix_hash to aggregate stats
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

      # Rewrite database with kept patterns only
      if pruned > 0
        db_path = File.join(MASTER.root, LearningFeedback::DB_FILE)
        File.open(db_path, "w") do |f|
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

    def exists?(description)
      all.any? { |l| l[:description] == description }
    end

    def rewrite(learnings)
      File.open(file_path, "w") do |f|
        learnings.each { |l| f.puts(JSON.generate(l)) }
      end
    end
  end

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
        p["category"] == finding.category.to_s
      end

      # Count successes
      successes = category_patterns.count { |p| p["success"] }
      total = category_patterns.size

      # Need at least 3 applications and >70% success rate
      total >= 3 && (successes.to_f / total) > 0.7
    end

    # Apply a known fix without LLM
    def apply_known(finding)
      patterns = load_patterns

      successful_patterns = patterns.select do |p|
        p["category"] == finding.category.to_s && p["success"]
      end

      return Result.err("No successful pattern found") if successful_patterns.empty?

      # Use the most recent successful pattern
      pattern = successful_patterns.last

      # This is a simplified implementation
      # In a real system, this would reconstruct and apply the actual fix
      Result.ok(applied: pattern["fix_hash"])
    end

    # Load all patterns from DB
    def load_patterns
      return [] unless File.exist?(db_path)

      File.readlines(db_path).map do |line|
        JSON.parse(line.strip)
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

  # LearningQuality - Assess and filter learning data quality
  module LearningQuality
    extend self

    MIN_CONFIDENCE = 0.6
    MINIMUM_APPLICATIONS = 3

    # Confidence scoring weights
    WEIGHT_CATEGORY = 0.3
    WEIGHT_SUCCESS = 0.3
    WEIGHT_TIMESTAMP = 0.2
    WEIGHT_FIX_HASH = 0.2

    TIERS = {
      promote: { threshold: 0.85, action: "Promote to core patterns" },
      keep: { threshold: 0.60, action: "Keep in active set" },
      demote: { threshold: 0.30, action: "Demote to experimental" },
      retire: { threshold: 0.0, action: "Retire pattern" }
    }.freeze

    def assess(learning)
      confidence = calculate_confidence(learning)
      {
        confidence: confidence,
        quality: confidence >= MIN_CONFIDENCE ? :acceptable : :low,
        usable: confidence >= MIN_CONFIDENCE
      }
    end

    def evaluate(pattern)
      applications = pattern["applications"] || pattern[:applications] || 0
      return :unrated if applications < MINIMUM_APPLICATIONS

      success_rate = calculate_success_rate(pattern)

      case success_rate
      when 0.85..Float::INFINITY then :promote
      when 0.60...0.85 then :keep
      when 0.30...0.60 then :demote
      else :retire
      end
    end

    def tier(pattern)
      evaluate(pattern)
    end

    def calculate_success_rate(pattern)
      successes = (pattern["successes"] || pattern[:successes] || 0).to_f
      failures = (pattern["failures"] || pattern[:failures] || 0).to_f
      total = successes + failures

      return 0.0 if total.zero?
      successes / total
    end

    private

    def calculate_confidence(learning)
      return 0.0 unless learning.is_a?(Hash)

      score = 0.0
      score += WEIGHT_CATEGORY if learning[:category]
      score += WEIGHT_SUCCESS if learning[:success]
      score += WEIGHT_TIMESTAMP if learning[:timestamp]
      score += WEIGHT_FIX_HASH if learning[:fix_hash]
      score
    end
  end

  # ReflectionMemory - Weighted learning from self-critiques with decay
  class ReflectionMemory
    DECAY_DAYS = 30
    DECAY_FACTOR = 0.4
    HIGH_PRIORITY_THRESHOLD = 0.75
    MAX_CONTEXT_ITEMS = 10

    def initialize(memory = nil)
      @memory = memory || Memory
    end

    def store_reflection(content:, strength:, task_id:, tags: [])
      @memory.remember(
        "#{content} | strength:#{strength} | task:#{task_id} | created:#{Time.now.to_i}",
        :long,
        tags: (tags + [:reflexion]).uniq
      )
    end

    def weighted_reflections(query: nil, limit: MAX_CONTEXT_ITEMS, tags: nil)
      search_tags = tags ? (Array(tags) + [:reflexion]).uniq : [:reflexion]

      raw_reflections = if query
                          @memory.search(query, tags: search_tags, limit: limit * 3)
                        else
                          @memory.recall(tags: search_tags, limit: limit * 3)
                        end

      now = Time.now.to_i

      weighted = raw_reflections.map do |ref|
        created_match = ref.match(/created:(\d+)/)
        created_at = created_match ? created_match[1].to_i : now

        strength_match = ref.match(/strength:([0-9.]+)/)
        strength = strength_match ? strength_match[1].to_f : 0.5

        age_days = (now - created_at) / 86_400.0

        decay_multiplier = age_days > DECAY_DAYS ? DECAY_FACTOR : 1.0
        adjusted_weight = strength * decay_multiplier

        {
          content: ref,
          strength: strength,
          age_days: age_days.round(1),
          decay: decay_multiplier,
          weight: adjusted_weight,
          priority: adjusted_weight >= HIGH_PRIORITY_THRESHOLD ? :high : :normal
        }
      end

      weighted.sort_by { |r| -r[:weight] }.first(limit)
    end

    def build_context_string(query: nil, limit: MAX_CONTEXT_ITEMS)
      reflections = weighted_reflections(query: query, limit: limit)

      high_priority = reflections.select { |r| r[:priority] == :high }
      normal_priority = reflections.select { |r| r[:priority] == :normal }

      parts = []

      if high_priority.any?
        parts << "HIGH PRIORITY LESSONS (strength > #{HIGH_PRIORITY_THRESHOLD}):"
        high_priority.first(4).each do |ref|
          parts << format_reflection(ref)
        end
      end

      if normal_priority.any?
        parts << "\nOTHER REFLECTIONS:"
        normal_priority.first(6).each do |ref|
          parts << format_reflection(ref)
        end
      end

      parts.join("\n")
    end

    def summarize_reflections(limit: 16, llm: nil)
      recent = weighted_reflections(limit: limit)
      return nil if recent.empty? || llm.nil?

      prompt = <<~PROMPT
        Analyze these self-critiques and extract 3 distilled lessons.
        Focus on patterns and actionable insights.

        Recent Reflections:
        #{recent.map { |r| "- [strength: #{r[:strength]}] #{r[:content]}" }.join("\n")}

        Provide 3 concise lessons (1 sentence each):
      PROMPT

      result = llm.ask(prompt, tier: :cheap)
      return nil unless result.ok?

      summary = result.value

      store_reflection(
        content: "DISTILLED: #{summary}",
        strength: 0.9,
        task_id: 'meta',
        tags: %i[distilled_lesson meta]
      )

      summary
    end

    private

    def format_reflection(ref)
      prefix = ref[:priority] == :high ? '  *' : '  -'
      decay_note = ref[:decay] < 1.0 ? " [aged #{ref[:age_days]}d, decayed]" : ''
      "#{prefix} [#{ref[:strength].round(2)}] #{ref[:content]}#{decay_note}"
    end
  end
end
