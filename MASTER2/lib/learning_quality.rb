# frozen_string_literal: true

module MASTER
  # LearningQuality - Pattern effectiveness tracking
  # Quality tiers: promote (>90% success), keep (50-90%), demote (20-50%), retire (<20%)
  # Requires minimum 3 applications before evaluating
  module LearningQuality
    extend self

    MIN_APPLICATIONS = 3

    TIER_THRESHOLDS = {
      promote: 0.90,  # >90% success rate - auto-apply
      keep: 0.50,     # 50-90% success rate
      demote: 0.20,   # 20-50% success rate
      retire: 0.0,    # <20% success rate
    }.freeze

    def evaluate_pattern(pattern)
      total = pattern[:success_count] + pattern[:fail_count]

      # Need minimum applications before evaluating
      return :keep if total < MIN_APPLICATIONS

      success_rate = pattern[:success_count].to_f / total

      case success_rate
      when TIER_THRESHOLDS[:promote]..1.0
        :promote
      when TIER_THRESHOLDS[:keep]...TIER_THRESHOLDS[:promote]
        :keep
      when TIER_THRESHOLDS[:demote]...TIER_THRESHOLDS[:keep]
        :demote
      else
        :retire
      end
    end

    def tier_description(tier)
      case tier
      when :promote
        "Auto-apply (>90% success)"
      when :keep
        "Manual review (50-90% success)"
      when :demote
        "Warning (20-50% success)"
      when :retire
        "Disabled (<20% success)"
      else
        "Unknown tier"
      end
    end

    def should_auto_apply?(pattern)
      evaluate_pattern(pattern) == :promote
    end

    def should_retire?(pattern)
      evaluate_pattern(pattern) == :retire
    end

    def quality_report
      return Result.err("LearningFeedback not available") unless defined?(MASTER::LearningFeedback)

      patterns = LearningFeedback.all_patterns
      tiers = { promote: [], keep: [], demote: [], retire: [], insufficient_data: [] }

      patterns.each do |pattern|
        total = pattern[:success_count] + pattern[:fail_count]
        if total < MIN_APPLICATIONS
          tiers[:insufficient_data] << pattern
        else
          tier = evaluate_pattern(pattern)
          tiers[tier] << pattern
        end
      end

      report = {
        total_patterns: patterns.size,
        tiers: tiers.transform_values(&:size),
        recommendations: build_recommendations(tiers),
      }

      Result.ok(report: report)
    rescue StandardError => e
      Result.err("Failed to generate quality report: #{e.message}")
    end

    def audit_patterns
      return Result.err("LearningFeedback not available") unless defined?(MASTER::LearningFeedback)
      return Result.err("Audit not available") unless defined?(MASTER::Audit)

      patterns = LearningFeedback.all_patterns
      report = Audit::Report.new

      patterns.each do |pattern|
        total = pattern[:success_count] + pattern[:fail_count]
        next if total < MIN_APPLICATIONS

        tier = evaluate_pattern(pattern)
        next if tier == :keep || tier == :promote

        severity = case tier
                   when :retire then :major
                   when :demote then :minor
                   else :info
                   end

        report.add(Audit::Finding.new(
          type: :poor_pattern_quality,
          severity: severity,
          effort: :low,
          file: "learning_feedback",
          message: "Pattern #{pattern[:id]} has #{tier} tier (#{pattern[:success_count]}/#{total} success)",
          fix_suggestion: tier == :retire ? "Remove pattern" : "Review and improve pattern",
        ))
      end

      Result.ok(report: report)
    rescue StandardError => e
      Result.err("Failed to audit patterns: #{e.message}")
    end

    def tier_stats
      return Result.err("LearningFeedback not available") unless defined?(MASTER::LearningFeedback)

      patterns = LearningFeedback.all_patterns
      stats = {
        promote: { count: 0, avg_success_rate: 0.0 },
        keep: { count: 0, avg_success_rate: 0.0 },
        demote: { count: 0, avg_success_rate: 0.0 },
        retire: { count: 0, avg_success_rate: 0.0 },
        insufficient_data: { count: 0, avg_success_rate: 0.0 },
      }

      patterns.each do |pattern|
        total = pattern[:success_count] + pattern[:fail_count]
        tier = total < MIN_APPLICATIONS ? :insufficient_data : evaluate_pattern(pattern)
        success_rate = total.zero? ? 0.0 : pattern[:success_count].to_f / total

        stats[tier][:count] += 1
        stats[tier][:avg_success_rate] += success_rate
      end

      # Calculate averages
      stats.each do |tier, data|
        data[:avg_success_rate] = data[:count].zero? ? 0.0 : (data[:avg_success_rate] / data[:count] * 100).round(2)
      end

      Result.ok(stats: stats)
    rescue StandardError => e
      Result.err("Failed to calculate tier stats: #{e.message}")
    end

    private

    def build_recommendations(tiers)
      recommendations = []

      if tiers[:retire].any?
        recommendations << "Retire #{tiers[:retire].size} low-quality patterns"
      end

      if tiers[:demote].any?
        recommendations << "Review #{tiers[:demote].size} patterns with declining quality"
      end

      if tiers[:promote].any?
        recommendations << "Enable auto-apply for #{tiers[:promote].size} high-quality patterns"
      end

      if tiers[:insufficient_data].any?
        recommendations << "#{tiers[:insufficient_data].size} patterns need more data (< #{MIN_APPLICATIONS} applications)"
      end

      recommendations
    end
  end
end
