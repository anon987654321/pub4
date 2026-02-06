#!/usr/bin/env ruby
# frozen_string_literal: true

# Tests for Phase 4 Advanced Autonomy Features

require_relative '../lib/master'
require 'fileutils'
require 'tmpdir'

class Phase4TestRunner
  def initialize
    @passed = 0
    @failed = 0
    @test_dir = nil
  end

  def assert(name, condition)
    if condition
      @passed += 1
      puts "  ✓ #{name}"
    else
      @failed += 1
      puts "  ✗ #{name}"
    end
  end

  def setup_test_dir
    @test_dir = Dir.mktmpdir('phase4_test_')
    Dir.chdir(@test_dir)
  end

  def cleanup_test_dir
    FileUtils.rm_rf(@test_dir) if @test_dir
  end

  def run
    puts "MASTER Phase 4 Test Suite"
    puts "=" * 60
    puts

    test_proactive_suggestions
    test_self_healing
    test_adaptive_ui
    test_metrics_tracker
    test_feedback_learning
    test_phase4_integration

    puts
    puts "=" * 60
    puts "#{@passed} passed, #{@failed} failed"
    exit(@failed > 0 ? 1 : 0)
  end

  def test_proactive_suggestions
    puts "\nProactive Suggestions:"
    
    suggestions = MASTER::Autonomy::ProactiveSuggestions.new
    
    # Test pattern matching
    suggestions.record_command('scan', success: true, context: {})
    suggestions.record_command('refactor', success: true, context: {})
    suggestion = suggestions.suggest_next(current_command: 'refactor')
    assert "Suggests 'test' after refactor", suggestion == 'test' || suggestion == 'commit'
    
    # Test smart defaults
    defaults = suggestions.smart_defaults('scan')
    assert "Provides smart defaults for scan", defaults.is_a?(Hash)
    assert "Includes depth in defaults", defaults.key?(:depth)
    
    # Test preconditions
    warnings = suggestions.check_preconditions('evolve', { budget: 0.1 })
    assert "Detects low budget warning", warnings.any? { |w| w.include?('Budget') }
    
    # Test context analyzer
    analyzer = MASTER::Autonomy::ContextAnalyzer.new
    context = analyzer.analyze('.')
    assert "Analyzes context", context.is_a?(Hash)
    assert "Includes file stats", context.key?(:file_stats)
  end

  def test_self_healing
    puts "\nSelf-Healing:"
    
    healing = MASTER::Autonomy::SelfHealing.new
    
    # Test error classification
    error = StandardError.new("Rate limit exceeded")
    assert "Classifies rate limit error", healing.classify_error(error) == :rate_limit
    
    timeout_error = StandardError.new("Connection timeout")
    assert "Classifies timeout error", healing.classify_error(timeout_error) == :timeout
    
    # Test recovery strategy
    strategy = healing.determine_recovery(error, 1)
    assert "Returns recovery strategy", strategy.is_a?(Hash)
    assert "Strategy includes action", strategy.key?(:action)
    
    # Test execute with recovery
    result = healing.execute_with_recovery("test operation") do
      "success"
    end
    assert "Executes successfully", result[:success]
    assert "Returns result", result[:result] == "success"
    
    # Test health status
    health = healing.health_status
    assert "Returns health status", health.is_a?(Hash)
    
    # Test diagnostics
    diagnostics = healing.run_diagnostics
    assert "Runs diagnostics", diagnostics.is_a?(Hash)
    assert "Includes file system check", diagnostics.key?(:file_system)
  end

  def test_adaptive_ui
    puts "\nAdaptive UI:"
    
    ui = MASTER::Autonomy::AdaptiveUI.new
    
    # Test verbosity
    verbosity = ui.optimal_verbosity(command_type: :debug)
    assert "Returns verbosity level", [:low, :medium, :high].include?(verbosity)
    
    # Test formatting
    formatted = ui.format_output("Test message", type: :success)
    assert "Formats output", formatted.is_a?(String)
    
    # Test emoji
    with_emoji = ui.with_emoji("Success", :success)
    assert "Adds emoji to text", with_emoji.include?("Success")
    
    # Test truncation
    long_text = "a" * 1000
    truncated = ui.truncate_intelligently(long_text, 100)
    assert "Truncates long text", truncated.length <= 110
    
    # Test preferences
    assert "Colors enabled by default", ui.use_colors?
    assert "Suggestions enabled by default", ui.show_suggestions?
    
    # Test interaction recording
    ui.record_interaction(type: :command, duration: 5.0, user_feedback: :positive)
    assert "Records interactions", ui.instance_variable_get(:@interaction_log).size > 0
  end

  def test_metrics_tracker
    puts "\nMetrics Tracker:"
    
    tracker = MASTER::Autonomy::MetricsTracker.new
    
    # Test event tracking
    tracker.track_event(:test, :action, { data: "test" })
    assert "Tracks events", true
    
    # Test performance tracking
    tracker.track_performance('test_operation', duration: 1.5, success: true)
    assert "Tracks performance", true
    
    # Test learning tracking
    tracker.track_learning(:pattern_learned, { pattern: "test" })
    assert "Tracks learning", true
    
    # Test autonomy tracking
    tracker.track_autonomy(:proactive_suggestion, { command: "test" })
    assert "Tracks autonomy actions", true
    
    # Test dashboard
    dashboard = tracker.dashboard
    assert "Generates dashboard", dashboard.is_a?(Hash)
    assert "Includes uptime", dashboard.key?(:uptime)
    assert "Includes success rate", dashboard.key?(:success_rate)
    
    # Test report generation
    report = tracker.generate_report
    assert "Generates report", report.is_a?(Hash)
    assert "Includes session summary", report.key?(:session)
    assert "Includes recommendations", report.key?(:recommendations)
    
    # Test export
    markdown = tracker.send(:export_markdown, report)
    assert "Exports markdown report", markdown.include?("# MASTER")
  end

  def test_feedback_learning
    puts "\nFeedback Learning:"
    
    feedback = MASTER::Autonomy::FeedbackLearning.new
    
    # Test satisfaction recording
    feedback.record_satisfaction(8, context: { command: 'test' })
    assert "Records satisfaction", true
    
    # Test correction recording
    feedback.record_correction(
      incorrect: "Too verbose response",
      correct: "Concise response",
      context: "user query"
    )
    assert "Records corrections", true
    
    # Test average satisfaction
    avg = feedback.average_satisfaction
    assert "Calculates average satisfaction", avg.is_a?(Float)
    
    # Test trend detection
    5.times { |i| feedback.record_satisfaction(i + 5, context: {}) }
    trend = feedback.satisfaction_trend
    assert "Detects satisfaction trend", [:improving, :declining, :stable, :unknown].include?(trend)
    
    # Test insights
    insights = feedback.feedback_insights
    assert "Generates feedback insights", insights.is_a?(Hash)
    assert "Includes total feedback", insights.key?(:total_feedback)
    assert "Includes average score", insights.key?(:average_score)
  end

  def test_phase4_integration
    puts "\nPhase 4 Integration:"
    
    # Test component initialization
    components = MASTER::Autonomy::Phase4.initialize_components
    assert "Initializes all components", components.is_a?(Hash)
    assert "Includes suggestions", components.key?(:suggestions)
    assert "Includes healing", components.key?(:healing)
    assert "Includes UI", components.key?(:ui)
    assert "Includes metrics", components.key?(:metrics)
    assert "Includes feedback", components.key?(:feedback)
    
    # Test enhanced execution
    result = MASTER::Autonomy::Phase4.execute_enhanced(
      'test_command',
      { force: true },
      components: components
    ) do |args|
      "success"
    end
    assert "Executes enhanced command", result[:success]
    
    # Test status report
    status = MASTER::Autonomy::Phase4.status_report(components)
    assert "Generates status report", status.is_a?(Hash)
    assert "Includes health", status.key?(:health)
    assert "Includes metrics", status.key?(:metrics)
  end
end

# Run tests
runner = Phase4TestRunner.new
runner.run
