#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple test for new features added in this PR
# Tests DecisionSupport, JSON export, and other improvements

require_relative "cli"
require "tempfile"
require "json"

def test_decision_support
  puts "Testing DecisionSupport module..."
  
  options = {
    "Option A" => { speed: 9, safety: 7, maintainability: 8 },
    "Option B" => { speed: 5, safety: 10, maintainability: 9 }
  }
  
  weights = { speed: 0.3, safety: 0.5, maintainability: 0.2 }
  
  scores = DecisionSupport.calculate_weights(options, weights)
  raise "Score calculation failed" if scores.empty?
  raise "Option A score incorrect" unless (scores["Option A"] - 7.7).abs < 0.1
  raise "Option B score incorrect" unless (scores["Option B"] - 8.3).abs < 0.1
  
  best_name, best_score, _all_scores = DecisionSupport.select_best(options, weights)
  raise "Best selection failed" unless best_name == "Option B"
  raise "Best score incorrect" unless (best_score - 8.3).abs < 0.1
  
  puts "  ✓ DecisionSupport.calculate_weights works correctly"
  puts "  ✓ DecisionSupport.select_best works correctly"
end

def test_governance_exporter
  puts "
Testing GovernanceExporter..."
  
  exporter = GovernanceExporter.new
  json_output = exporter.export_to_json
  
  raise "JSON export returned empty" if json_output.nil? || json_output.empty?
  
  data = JSON.parse(json_output)
  raise "Missing export_metadata" unless data["export_metadata"]
  raise "Missing governance_version" unless data["governance_version"]
  raise "Missing sections" unless data["sections"]
  
  required_sections = %w[meta style_constraints rules axioms testing security defect_catalog]
  required_sections.each do |section|
    raise "Missing section: #{section}" unless data["sections"][section]
  end
  
  puts "  ✓ JSON export generates valid structure"
  puts "  ✓ All required sections present"
end

def test_ui_handler
  puts "
Testing UIHandler..."
  
  ui = UIHandler.new
  
  # Test that methods don't raise errors
  begin
    ui.show_welcome("17.1.0", :user)
    ui.show_help
    ui.show_error("test error")
    ui.show_info("test info")
    ui.show_success("test success")
    puts "  ✓ UIHandler methods work without errors"
  rescue => e
    raise "UIHandler test failed: #{e.message}"
  end
end

def test_constants
  puts "
Testing hoisted constants..."
  
  raise "VERSION not defined" unless defined?(VERSION)
  raise "MAX_STDOUT_SIZE not defined" unless defined?(MAX_STDOUT_SIZE)
  raise "MAX_FILE_SIZE not defined" unless defined?(MAX_FILE_SIZE)
  raise "DEFAULT_MODEL not defined" unless defined?(DEFAULT_MODEL)
  raise "CONFIG_FILE_PERMISSIONS not defined" unless defined?(CONFIG_FILE_PERMISSIONS)
  
  puts "  ✓ All constants properly defined"
end

# Run all tests
begin
  puts "=" * 60
  puts "Running tests for new features..."
  puts "=" * 60
  
  test_constants
  test_decision_support
  test_governance_exporter
  test_ui_handler
  
  puts "
" + "=" * 60
  puts "✓ All tests passed!"
  puts "=" * 60
  exit 0
rescue => e
  puts "
" + "=" * 60
  puts "✗ Test failed: #{e.message}"
  puts e.backtrace.first(5).join("
")
  puts "=" * 60
  exit 1
end
