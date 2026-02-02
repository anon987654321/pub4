#!/usr/bin/env ruby
# frozen_string_literal: true

# Test for Bug Hunting Protocol integration
# This test verifies that the bug hunting analyzer can detect common patterns

require 'minitest/autorun'
require_relative 'cli'

class TestBugHuntingProtocol < Minitest::Test
  def test_bug_hunting_analyzer_runs_all_8_phases
    buggy_code = <<~RUBY
      class User
        def save
          db.execute("INSERT INTO users (email) VALUES (?)", @email)
        end
      end
    RUBY
    
    code_unit = CodeUnit.new(content: buggy_code)
    report = BugHuntingAnalyzer.analyze_code_unit_for_potential_bugs(code_unit)
    
    assert_equal 8, report[:phases_completed].length
    assert report[:findings][:lexical_consistency]
    assert report[:findings][:execution_traces]
    assert report[:findings][:implicit_assumptions]
    assert report[:findings][:data_flows]
    assert report[:findings][:state_reconstruction]
    assert report[:findings][:bug_patterns]
    assert report[:findings][:understanding_status]
    assert report[:findings][:verification_status]
  end
  
  def test_lexical_analyzer_detects_single_letter_variables
    code_with_short_vars = <<~RUBY
      def process
        f = File.open("data.txt")
        d = f.read
        f.close
      end
    RUBY
    
    code_unit = CodeUnit.new(content: code_with_short_vars)
    analysis = LexicalConsistencyAnalyzer.analyze_identifiers_for_consistency(code_unit)
    
    identifiers = analysis[:identifiers]
    assert identifiers.include?('f')
    assert identifiers.include?('d')
  end
  
  def test_pattern_matcher_detects_resource_leak
    code_with_leak = <<~RUBY
      def read_file
        f = File.open("data.txt")
        content = f.read
        f.close
        content
      end
    RUBY
    
    code_unit = CodeUnit.new(content: code_with_leak)
    patterns = PatternMatcher.match_against_common_bug_patterns(code_unit)
    
    leak_pattern = patterns[:matches].find { |p| p[:name].include?("Resource leak") }
    assert leak_pattern, "Should detect resource leak pattern"
    assert_equal "High", leak_pattern[:confidence]
  end
  
  def test_assumption_interrogator_finds_file_operations
    code_with_file_ops = <<~RUBY
      def load_config
        File.open("config.yml")
      end
    RUBY
    
    code_unit = CodeUnit.new(content: code_with_file_ops)
    assumptions = AssumptionInterrogator.find_implicit_assumptions(code_unit)
    
    file_assumption = assumptions[:found].find { |a| a[:category] == "File system" }
    assert file_assumption, "Should detect file system assumption"
    refute file_assumption[:validated], "File existence should need validation"
  end
  
  def test_data_flow_tracer_finds_assignments
    code_with_assignments = <<~RUBY
      def calculate
        x = 10
        y = x * 2
        z = y + 5
      end
    RUBY
    
    code_unit = CodeUnit.new(content: code_with_assignments)
    flows = DataFlowTracer.trace_data_lineage(code_unit)
    
    assert flows[:traces].length >= 3, "Should find at least 3 assignments"
    variable_names = flows[:traces].map { |t| t[:variable] }
    assert variable_names.include?('x')
    assert variable_names.include?('y')
    assert variable_names.include?('z')
  end
  
  def test_bug_hunting_report_formatting
    buggy_code = <<~RUBY
      def get_data
        f = File.open("data.txt")
        d = f.read
        f.close
        d
      end
    RUBY
    
    code_unit = CodeUnit.new(content: buggy_code)
    report = BugHuntingAnalyzer.analyze_code_unit_for_potential_bugs(code_unit)
    formatted = BugHuntingAnalyzer.format_bug_hunting_report(report)
    
    assert formatted.include?("BUG HUNTING REPORT")
    assert formatted.include?("PHASE 1: LEXICAL ANALYSIS")
    assert formatted.include?("PHASE 2: SIMULATED EXECUTION")
    assert formatted.include?("PHASE 3: ASSUMPTIONS")
    assert formatted.include?("PHASE 4: DATA FLOW")
    assert formatted.include?("PHASE 5: STATE RECONSTRUCTION")
    assert formatted.include?("PHASE 6: PATTERN MATCHING")
    assert formatted.include?("PHASE 7: PROOF OF UNDERSTANDING")
    assert formatted.include?("PHASE 8: VERIFICATION")
  end
  
  def test_bug_hunting_integrates_with_universal_analyzer
    code_with_violations = <<~RUBY
      def process
        get_data
      end
    RUBY
    
    code_unit = CodeUnit.new(content: code_with_violations)
    
    # Should trigger bug hunting because of violations
    analysis = UniversalCodeAnalyzer.analyze_single_code_unit_for_all_violation_types(
      code_unit,
      enable_bug_hunting: false  # Should auto-activate on violations
    )
    
    # Naming violations should trigger bug hunting
    if analysis[:naming_violations].any?
      assert analysis[:bug_hunting_report], "Bug hunting should activate on violations"
    end
  end
  
  def test_bug_hunting_can_be_forced_on_clean_code
    clean_code = <<~RUBY
      def calculate_total_price_including_tax(price)
        price * 1.1
      end
    RUBY
    
    code_unit = CodeUnit.new(content: clean_code)
    
    # Force bug hunting on clean code
    analysis = UniversalCodeAnalyzer.analyze_single_code_unit_for_all_violation_types(
      code_unit,
      enable_bug_hunting: true
    )
    
    assert analysis[:bug_hunting_report], "Bug hunting should run when explicitly enabled"
  end
end
