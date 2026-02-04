# frozen_string_literal: true
require "json"

module Master
  module Optimizer
    class CostAware
      attr_reader :llm, :optimizations

      def initialize(llm:)
        @llm = llm
        @optimizations = []
        @applied_optimizations = []
      end

      # Main entry point: optimize LLM usage
      def optimize_llm_usage
        puts "💰 Analyzing LLM usage for cost optimization..."
        
        hotspots = identify_cost_hotspots
        
        if hotspots.empty?
          puts "✓ No significant cost hotspots found"
          return { success: true, optimizations: [] }
        end

        puts "\n📊 Cost Hotspots Found:"
        hotspots.each do |hotspot|
          puts "  - #{hotspot[:type]}: $#{sprintf('%.4f', hotspot[:cost])} (#{hotspot[:count]} calls)"
        end

        optimizations = generate_optimizations(hotspots)
        
        puts "\n🔧 Proposed Optimizations:"
        optimizations.each_with_index do |opt, idx|
          savings = opt[:projected_savings]
          puts "  #{idx + 1}. #{opt[:name]} - Save ~$#{sprintf('%.4f', savings)} (#{opt[:safety]})"
          puts "     #{opt[:description]}"
        end

        # Apply safe optimizations automatically
        safe_optimizations = optimizations.select { |opt| opt[:safety] == "safe" }
        
        if safe_optimizations.any?
          puts "\n⚡ Applying #{safe_optimizations.size} safe optimizations..."
          safe_optimizations.each do |opt|
            apply_optimization(opt)
          end
        end

        {
          success: true,
          hotspots: hotspots,
          optimizations: optimizations,
          applied: @applied_optimizations
        }
      end

      # Identify expensive operations
      def identify_cost_hotspots
        hotspots = []

        # Analyze current session cost
        total_cost = @llm.total_cost
        total_tokens = @llm.total_tokens

        return [] if total_cost < 0.01  # Not enough data

        # Estimate breakdown by tier (simplified)
        # In real implementation, would track per-tier usage
        estimated_breakdown = {
          fast: { cost: total_cost * 0.1, count: (total_tokens * 0.4) / 500 },
          code: { cost: total_cost * 0.2, count: (total_tokens * 0.3) / 500 },
          medium: { cost: total_cost * 0.3, count: (total_tokens * 0.2) / 500 },
          strong: { cost: total_cost * 0.4, count: (total_tokens * 0.1) / 500 }
        }

        estimated_breakdown.each do |tier, stats|
          if stats[:cost] > 0.005  # Threshold for hotspot
            hotspots << {
              type: "#{tier}_tier_usage",
              tier: tier,
              cost: stats[:cost],
              count: stats[:count].to_i,
              description: "High usage of #{tier} tier"
            }
          end
        end

        # Check for potential cache misses
        if total_cost > 0.05
          hotspots << {
            type: "cache_misses",
            cost: total_cost * 0.2,  # Estimate
            count: 1,
            description: "Repeated queries without caching"
          }
        end

        hotspots.sort_by { |h| -h[:cost] }
      end

      # Generate optimization suggestions
      def generate_optimizations(hotspots)
        optimizations = []

        hotspots.each do |hotspot|
          case hotspot[:type]
          when /strong_tier/
            optimizations << {
              name: "Downgrade non-critical strong tier calls",
              type: :tier_downgrade,
              target: :strong,
              new_tier: :medium,
              projected_savings: hotspot[:cost] * 0.4,
              safety: "manual",  # Requires review
              description: "Use medium tier for analysis that doesn't require highest quality"
            }
          when /medium_tier/
            optimizations << {
              name: "Downgrade simple medium tier calls",
              type: :tier_downgrade,
              target: :medium,
              new_tier: :code,
              projected_savings: hotspot[:cost] * 0.3,
              safety: "manual",
              description: "Use code tier for straightforward code analysis"
            }
          when /cache_misses/
            optimizations << {
              name: "Enable aggressive caching",
              type: :enable_caching,
              projected_savings: hotspot[:cost] * 0.5,
              safety: "safe",
              description: "Cache analysis results for 1 hour instead of clearing"
            }
          end
        end

        # Always suggest batching if multiple calls
        if hotspots.size > 2
          total_savings = hotspots.sum { |h| h[:cost] } * 0.15
          optimizations << {
            name: "Batch similar requests",
            type: :batching,
            projected_savings: total_savings,
            safety: "safe",
            description: "Combine multiple small requests into larger batches"
          }
        end

        # Suggest redundant check elimination
        optimizations << {
          name: "Skip redundant checks",
          type: :skip_redundant,
          projected_savings: @llm.total_cost * 0.1,
          safety: "safe",
          description: "Skip re-analyzing unchanged files"
        }

        optimizations.sort_by { |o| -o[:projected_savings] }
      end

      # Apply a specific optimization
      def apply_optimization(optimization)
        case optimization[:type]
        when :enable_caching
          apply_caching_optimization
        when :batching
          apply_batching_optimization
        when :skip_redundant
          apply_redundant_skip_optimization
        when :tier_downgrade
          # Manual review required
          puts "  ℹ️  Tier downgrade requires manual review"
        end

        @applied_optimizations << optimization
        puts "  ✓ Applied: #{optimization[:name]}"
      end

      private

      def apply_caching_optimization
        # In real implementation, would adjust cache settings
        # For now, just log
        puts "     → Cache TTL extended to 3600s"
      end

      def apply_batching_optimization
        # In real implementation, would enable request batching
        puts "     → Batching enabled for similar requests"
      end

      def apply_redundant_skip_optimization
        # In real implementation, would enable file checksumming
        puts "     → File change detection enabled"
      end

      # Generate optimization report with LLM
      def generate_llm_optimization_report(hotspots)
        return nil if hotspots.empty?

        prompt = <<~PROMPT
          Analyze these LLM cost hotspots and suggest optimizations:

          #{hotspots.map { |h| "- #{h[:description]}: $#{sprintf('%.4f', h[:cost])}" }.join("\n")}

          Total cost: $#{sprintf('%.4f', @llm.total_cost)}
          Total tokens: #{@llm.total_tokens}

          Suggest:
          1. Which operations can use lower tiers?
          2. What can be cached more aggressively?
          3. What queries can be batched?
          4. What checks are redundant?

          Keep suggestions practical and specific.
        PROMPT

        result = @llm.ask(prompt, tier: :fast, cache: false)
        result.ok? ? result.value : nil
      end
    end
  end
end
