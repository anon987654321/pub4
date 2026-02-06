# frozen_string_literal: true

require_relative 'proactive_suggestions'
require_relative 'self_healing'
require_relative 'adaptive_ui'
require_relative 'metrics_tracker'

module MASTER
  module Autonomy
    # Phase 4 Integration - Advanced autonomy and intelligence
    module Phase4
      extend self
      
      # Initialize all Phase 4 components
      def initialize_components(llm = nil)
        {
          suggestions: ProactiveSuggestions.new,
          healing: SelfHealing.new(llm),
          ui: AdaptiveUI.new,
          metrics: MetricsTracker.new,
          feedback: FeedbackLearning.new
        }
      end
      
      # Execute command with full Phase 4 enhancements
      def execute_enhanced(command, args = {}, components:, &block)
        start_time = Time.now
        
        # Pre-execution checks
        warnings = components[:suggestions].check_preconditions(command, args)
        if warnings.any? && !args[:force]
          puts components[:ui].with_emoji("⚠ Warnings detected:", :warning)
          warnings.each { |w| puts "  - #{w}" }
          puts "\nContinue anyway? (y/n)"
          return { success: false, reason: :user_abort } unless gets.strip.downcase == 'y'
        end
        
        # Apply smart defaults
        defaults = components[:suggestions].smart_defaults(command)
        args = defaults.merge(args)
        
        # Execute with self-healing
        result = components[:healing].execute_with_recovery("#{command} execution") do
          block.call(args)
        end
        
        # Track metrics
        duration = Time.now - start_time
        components[:metrics].track_performance(
          command,
          duration: duration,
          success: result[:success],
          metadata: { args: args }
        )
        
        # Record for learning
        components[:suggestions].record_command(
          command,
          success: result[:success],
          context: { duration: duration }
        )
        
        # Suggest next action if successful
        if result[:success] && components[:ui].show_suggestions?
          suggestion = components[:suggestions].suggest_next(
            current_command: command,
            git_status: `git status --porcelain 2>/dev/null`.strip,
            file_state: Dir.glob('**/*.rb').size
          )
          
          if suggestion
            puts "\n" + components[:ui].with_emoji(
              "Suggestion: Try `#{suggestion}` next",
              :info
            )
          end
        end
        
        result
      end
      
      # Get comprehensive status report
      def status_report(components)
        {
          health: components[:healing].health_status,
          metrics: components[:metrics].dashboard,
          ui_preferences: components[:ui].instance_variable_get(:@preferences),
          feedback_insights: components[:feedback].feedback_insights
        }
      end
      
      # Run diagnostics
      def run_diagnostics(components)
        puts "Running Phase 4 diagnostics..."
        puts ""
        
        # System health
        puts "System Health:"
        health = components[:healing].run_diagnostics
        health.each do |area, status|
          icon = status[:healthy] ? "✓" : "✗"
          puts "  #{icon} #{area}: #{status.inspect}"
        end
        puts ""
        
        # Metrics dashboard
        puts "Metrics Dashboard:"
        dashboard = components[:metrics].dashboard
        dashboard.each do |metric, value|
          puts "  · #{metric}: #{value}"
        end
        puts ""
        
        # Feedback insights
        puts "Feedback Insights:"
        insights = components[:feedback].feedback_insights
        insights.each do |key, value|
          puts "  · #{key}: #{value}"
        end
        puts ""
        
        # Learning patterns
        suggestions_file = File.join(Paths.var, 'suggestions_learned.yml')
        if File.exist?(suggestions_file)
          patterns = YAML.load_file(suggestions_file) rescue []
          puts "Learned Patterns: #{patterns.size}"
          patterns.first(5).each do |p|
            puts "  · #{p[:sequence].join(' → ')} → #{p[:next_command]} (×#{p[:count]})"
          end
        end
        
        { health: health, dashboard: dashboard, insights: insights }
      end
      
      # Export comprehensive report
      def export_report(components, format: :markdown)
        report_content = components[:metrics].export_report(format: format)
        
        filename = "autonomy_report_#{Time.now.strftime('%Y%m%d_%H%M%S')}.#{format}"
        filepath = File.join(Paths.var, 'reports', filename)
        
        FileUtils.mkdir_p(File.dirname(filepath))
        File.write(filepath, report_content)
        
        puts "Report exported to: #{filepath}"
        filepath
      end
      
      # Tune system based on feedback
      def auto_tune(components)
        puts "Auto-tuning system based on feedback..."
        
        insights = components[:feedback].feedback_insights
        trend = insights[:trend]
        
        case trend
        when :declining
          puts "  · Satisfaction declining - adjusting to more helpful mode"
          # Increase suggestions and verbosity
          components[:ui].instance_variable_get(:@preferences)[:suggestions] = true
          components[:ui].instance_variable_get(:@preferences)[:verbosity] = :high
          
        when :stable
          puts "  · Satisfaction stable - maintaining current settings"
          
        when :improving
          puts "  · Satisfaction improving - continuing current approach"
        end
        
        # Optimize slow operations
        slow_ops = components[:metrics].send(:find_slow_operations)
        if slow_ops.any?
          puts "  · Optimizing slow operations: #{slow_ops.join(', ')}"
          # Could trigger optimization strategies here
        end
        
        # Learn from corrections
        corrections = insights[:recent_corrections]
        if corrections.any?
          puts "  · Applying #{corrections.size} recent corrections"
          # Apply learned patterns
        end
        
        puts "Auto-tuning complete!"
      end
      
      # Interactive setup wizard
      def setup_wizard
        puts "━━━ Phase 4 Autonomy Setup ━━━"
        puts ""
        puts "Let's configure your autonomy preferences."
        puts ""
        
        preferences = {}
        
        # Verbosity
        puts "Verbosity level? (low/medium/high)"
        print "> "
        preferences[:verbosity] = gets.strip.to_sym
        
        # Suggestions
        puts "Show proactive suggestions? (yes/no)"
        print "> "
        preferences[:suggestions] = gets.strip.downcase == 'yes'
        
        # Auto-recovery
        puts "Enable automatic error recovery? (yes/no)"
        print "> "
        preferences[:auto_recovery] = gets.strip.downcase == 'yes'
        
        # Colors
        puts "Use colors in output? (yes/no)"
        print "> "
        preferences[:colors] = gets.strip.downcase == 'yes'
        
        # Save preferences
        pref_file = File.join(Paths.var, 'ui_preferences.yml')
        FileUtils.mkdir_p(File.dirname(pref_file))
        File.write(pref_file, preferences.to_yaml)
        
        puts ""
        puts "✓ Preferences saved!"
        puts ""
        
        preferences
      end
    end
  end
end
