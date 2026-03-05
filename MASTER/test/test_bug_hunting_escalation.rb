# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestBugHuntingEscalation < Minitest::Test
  def test_escalation_levels_constant_exists
    assert defined?(MASTER::BugHunting::ESCALATION_LEVELS), "ESCALATION_LEVELS should exist"
  end

  def test_escalation_has_four_levels
    levels = MASTER::BugHunting::ESCALATION_LEVELS
    assert_equal 4, levels.size
    assert_equal [:syntax, :logic, :history, :llm], levels
  end

  def test_hunt_method_exists
    assert_respond_to MASTER::BugHunting, :hunt
  end

  def test_hunt_with_auto_level
    require "tempfile"
    
    Tempfile.create(['test', '.rb']) do |f|
      f.write("def test\n  puts 'hello'\nend\n")
      f.flush
      
      result = MASTER::BugHunting.hunt(f.path, level: :auto)
      assert result.is_a?(Hash), "Hunt should return a hash"
      assert result.key?(:level), "Result should include level"
    end
  end

  def test_hunt_with_specific_level
    require "tempfile"
    
    Tempfile.create(['test', '.rb']) do |f|
      f.write("def test\n  puts 'hello'\nend\n")
      f.flush
      
      result = MASTER::BugHunting.hunt(f.path, level: :syntax)
      assert result.is_a?(Hash), "Hunt should return a hash"
      assert_equal :syntax, result[:level]
    end
  end

  def test_syntax_level_detects_valid_ruby
    require "tempfile"
    
    Tempfile.create(['test', '.rb']) do |f|
      f.write("def valid_method\n  42\nend\n")
      f.flush
      
      result = MASTER::BugHunting.send(:level_syntax, f.path)
      assert result[:level] == :syntax
      refute result[:fixed], "Valid syntax should not be marked as fixed"
    end
  end
end
