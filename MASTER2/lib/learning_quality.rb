# frozen_string_literal: true

module MASTER
  # LearningQuality - Quality tier evaluation for learned patterns
  module LearningQuality
    extend self

    # Quality tiers based on success rate
    TIERS = {
      promote: { min: 0.90, description: "Auto-apply (>90% success)" },
      keep: { min: 0.50, description: "Keep learning (50-90%)" },
      demote: { min: 0.20, description: "Needs review (20-50%)" },
      retire: { min: 0.00, description: "Remove (<20%)" }
    }.freeze

    MINIMUM_APPLICATIONS = 3

    # Evaluate a pattern and return its tier
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

    # Get current tier for a pattern
    def tier(pattern)
      evaluate(pattern)
    end

    # Calculate success rate from pattern
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
  end
end
